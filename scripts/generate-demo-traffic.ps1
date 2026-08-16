<#
.SYNOPSIS
    Genera trafico mixto (exitoso + con error) contra dispatch-service y
    triage-service para poblar Grafana / X-Ray / CloudWatch con datos reales.

.DESCRIPTION
    Pensado para correr contra el ALB de dev. No requiere nada instalado
    aparte de PowerShell (usa Invoke-WebRequest).

.PARAMETER AlbHost
    DNS del ALB. Default: el de dev.

.PARAMETER Rounds
    Cuantas veces repetir el ciclo completo de requests. Default 1.

.PARAMETER DelayMs
    Pausa entre requests, en milisegundos. Default 300.

.EXAMPLE
    .\generate-demo-traffic.ps1
    .\generate-demo-traffic.ps1 -Rounds 5 -DelayMs 500
#>
param(
    [string]$AlbHost = "emergency-ops-alb-268713301.us-east-1.elb.amazonaws.com",
    [int]$Rounds = 1,
    [int]$DelayMs = 300
)

$ErrorActionPreference = "Continue"
$base = "http://$AlbHost"

$stats = @{ ok = 0; err = 0 }

function Invoke-Demo {
    param(
        [string]$Label,
        [string]$Method,
        [string]$Path,
        [string]$Body = $null
    )
    $uri = "$base$Path"
    try {
        if ($Body) {
            $resp = Invoke-WebRequest -Uri $uri -Method $Method -ContentType "application/json" -Body $Body -TimeoutSec 15 -UseBasicParsing
        } else {
            $resp = Invoke-WebRequest -Uri $uri -Method $Method -TimeoutSec 15 -UseBasicParsing
        }
        $code = [int]$resp.StatusCode
        $script:stats.ok++
        Write-Host ("[{0,3}] {1,-28} {2}" -f $code, $Label, $Method) -ForegroundColor Green
        return $resp.Content
    } catch {
        $code = "?"
        if ($_.Exception.Response) {
            $code = [int]$_.Exception.Response.StatusCode
        }
        $script:stats.err++
        Write-Host ("[{0,3}] {1,-28} {2}  <- esperado" -f $code, $Label, $Method) -ForegroundColor Yellow
        return $null
    } finally {
        Start-Sleep -Milliseconds $DelayMs
    }
}

function New-ReportId {
    return "DEMO-$(Get-Date -Format 'HHmmss')-$(Get-Random -Maximum 99999)"
}

Write-Host "=== Generando trafico de demo contra $base ===" -ForegroundColor Cyan

for ($round = 1; $round -le $Rounds; $round++) {
    Write-Host "`n--- Ronda $round de $Rounds ---" -ForegroundColor Cyan

    # ---------------------------------------------------------------
    # TRIAGE: casos validos que disparan cada prioridad
    # ---------------------------------------------------------------
    $triageCasesOk = @(
        @{ label = "triage RED (dolor toracico)"; body = @{
                report_id = New-ReportId; patient_age = 55
                symptoms = @("dolor torácico"); description = "demo"
            } },
        @{ label = "triage YELLOW (fiebre alta)"; body = @{
                report_id = New-ReportId; patient_age = 30
                symptoms = @("fiebre alta"); description = "demo"
            } },
        @{ label = "triage GREEN (sin alarma)"; body = @{
                report_id = New-ReportId; patient_age = 25
                symptoms = @("tos leve"); description = "demo"
            } },
        @{ label = "triage YELLOW (fractura)"; body = @{
                report_id = New-ReportId; patient_age = 40
                symptoms = @("fractura visible"); description = "demo"
            } }
    )

    $lastReportId = $null
    foreach ($c in $triageCasesOk) {
        $json = $c.body | ConvertTo-Json
        $result = Invoke-Demo -Label $c.label -Method "POST" -Path "/triage" -Body $json
        if ($result) { $lastReportId = ($result | ConvertFrom-Json).report_id }
    }

    # GET valido: consultar el ultimo reporte creado
    if ($lastReportId) {
        Invoke-Demo -Label "GET triage (existe)" -Method "GET" -Path "/triage/$lastReportId" | Out-Null
    }

    # ---------------------------------------------------------------
    # TRIAGE: casos invalidos (400) -- errores esperados
    # ---------------------------------------------------------------
    $triageCasesErr = @(
        @{ label = "triage sin report_id (400)"; body = @{
                patient_age = 30; symptoms = @("fiebre alta"); description = "demo"
            } },
        @{ label = "triage sin sintomas (400)"; body = @{
                report_id = New-ReportId; patient_age = 30
                symptoms = @(); description = "demo"
            } },
        @{ label = "triage edad invalida (400)"; body = @{
                report_id = New-ReportId; patient_age = 200
                symptoms = @("fiebre alta"); description = "demo"
            } }
    )
    foreach ($c in $triageCasesErr) {
        $json = $c.body | ConvertTo-Json
        Invoke-Demo -Label $c.label -Method "POST" -Path "/triage" -Body $json | Out-Null
    }

    # GET invalido: reporte que no existe (404)
    Invoke-Demo -Label "GET triage (no existe, 404)" -Method "GET" -Path "/triage/NO-EXISTE-$(Get-Random)" | Out-Null

    # ---------------------------------------------------------------
    # DISPATCH: casos validos (ojo: el pool de ambulancias es finito y
    # no se libera, asi que despues de las primeras esto empieza a dar
    # 503 NO_AVAILABLE_AMBULANCE solo -- eso tambien es trafico de error
    # real y utilo para el dashboard).
    # ---------------------------------------------------------------
    # OJO: el DTO de POST /dispatch usa campos PLANOS incident_latitude /
    # incident_longitude, NO un objeto anidado incident_location. Go ignora
    # silenciosamente campos JSON desconocidos, asi que un payload con el
    # nombre equivocado "pasa" pero con lat/long en 0 -- es exactamente el
    # bug que aparecia como "incident_latitude en 0" que habiamos anotado
    # como limitacion de la app: en realidad era el payload de prueba.
    $dispatchOk = @{
        report_id = New-ReportId; patient_age = 45
        symptoms = @("dolor torácico"); description = "demo"
        incident_latitude = 40.4168; incident_longitude = -3.7038
    } | ConvertTo-Json
    Invoke-Demo -Label "dispatch valido" -Method "POST" -Path "/dispatch" -Body $dispatchOk | Out-Null

    # ---------------------------------------------------------------
    # DISPATCH: casos invalidos (400)
    # ---------------------------------------------------------------
    $dispatchCasesErr = @(
        @{ label = "dispatch sin report_id (400)"; body = @{
                patient_age = 45; symptoms = @("fiebre alta")
                incident_latitude = 40.4; incident_longitude = -3.7
            } },
        @{ label = "dispatch coordenadas invalidas (400)"; body = @{
                report_id = New-ReportId; patient_age = 45
                symptoms = @("fiebre alta")
                incident_latitude = 200; incident_longitude = -3.7
            } },
        @{ label = "dispatch sin sintomas (400)"; body = @{
                report_id = New-ReportId; patient_age = 45
                symptoms = @()
                incident_latitude = 40.4; incident_longitude = -3.7
            } }
    )
    foreach ($c in $dispatchCasesErr) {
        $json = $c.body | ConvertTo-Json
        Invoke-Demo -Label $c.label -Method "POST" -Path "/dispatch" -Body $json | Out-Null
    }

    # GET invalido: dispatch que no existe (404)
    Invoke-Demo -Label "GET dispatch (no existe, 404)" -Method "GET" -Path "/dispatch/NO-EXISTE-$(Get-Random)" | Out-Null
}

Write-Host "`n=== Listo ===" -ForegroundColor Cyan
Write-Host "Respuestas 2xx: $($stats.ok)   Respuestas de error (esperadas): $($stats.err)"
Write-Host "Dale unos 15-30s y mira Grafana / X-Ray / CloudWatch Logs Insights (busca por trace_id)."
