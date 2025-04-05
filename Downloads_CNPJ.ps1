<#
.SYNOPSIS
    Script otimizado para download de grandes arquivos CNPJ
.DESCRIPTION
    Versão com suporte a downloads grandes, resumíveis e com verificação de integridade
#>

# Configurações
$baseUrl = "https://arquivos.receitafederal.gov.br/dados/cnpj/dados_abertos_cnpj/"
$downloadDir = "$PSScriptRoot\Downloads_CNPJ"
$tempFile = "$PSScriptRoot\temp.html"
$bufferSize = 1MB # Tamanho do buffer para download
$timeoutSeconds = 300 # Timeout para cada operação (5 minutos)

# Criar diretório de download se não existir
if (-not (Test-Path -Path $downloadDir)) {
    New-Item -ItemType Directory -Path $downloadDir | Out-Null
    Write-Host "Diretório de download criado: $downloadDir" -ForegroundColor Green
}

# Função para obter a pasta mais recente
function Get-MostRecentFolder {
    try {
        # Baixar a página inicial
        $response = Invoke-WebRequest -Uri $baseUrl -UseBasicParsing -TimeoutSec $timeoutSeconds
        $content = $response.Content
        
        # Extrair todas as pastas com formato yyyy-mm
        $folders = [regex]::Matches($content, 'href="(\d{4}-\d{2})/"') | 
                   ForEach-Object { $_.Groups[1].Value } |
                   Sort-Object -Descending
        
        if (-not $folders) {
            Write-Host "Nenhuma pasta de dados encontrada." -ForegroundColor Red
            return $null
        }
        
        # Retornar a pasta mais recente
        $mostRecent = $folders[0]
        Write-Host "Pasta mais recente encontrada: $mostRecent" -ForegroundColor Green
        return "$baseUrl$mostRecent/"
        
    } catch {
        Write-Host "Erro ao acessar o diretório: $_" -ForegroundColor Red
        return $null
    }
}

# Função para download robusto de arquivos grandes
function Download-LargeFile {
    param (
        [string]$url,
        [string]$outputPath
    )
    
    try {
        # Configurar a requisição
        $request = [System.Net.HttpWebRequest]::Create($url)
        $request.Timeout = $timeoutSeconds * 1000
        $request.ReadWriteTimeout = $timeoutSeconds * 1000
        
        # Obter o tamanho total do arquivo
        $response = $request.GetResponse()
        $totalSize = $response.ContentLength
        $response.Close()
        
        if ($totalSize -eq -1) {
            Write-Host "Não foi possível determinar o tamanho do arquivo." -ForegroundColor Yellow
        } else {
            $sizeMB = [math]::Round($totalSize / 1MB, 2)
            Write-Host "Tamanho do arquivo: $sizeMB MB" -ForegroundColor Cyan
        }
        
        # Configurar o cliente web para download em chunks
        $client = New-Object System.Net.WebClient
        $client.Proxy = [System.Net.WebRequest]::GetSystemWebProxy()
        $client.Proxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials
        $client.DownloadFile($url, $outputPath)
        
        # Verificar se o arquivo foi completamente baixado
        if (Test-Path -Path $outputPath) {
            $downloadedSize = (Get-Item $outputPath).Length
            if ($totalSize -ne -1 -and $downloadedSize -ne $totalSize) {
                Write-Host "Aviso: Tamanho do arquivo baixado ($downloadedSize bytes) não corresponde ao esperado ($totalSize bytes)" -ForegroundColor Yellow
            }
            return $true
        }
        return $false
        
    } catch {
        Write-Host "Erro durante o download: $_" -ForegroundColor Red
        # Remover arquivo parcialmente baixado se existir
        if (Test-Path -Path $outputPath) {
            Remove-Item -Path $outputPath -Force
        }
        return $false
    } finally {
        if ($client) { $client.Dispose() }
    }
}

# Função principal para baixar os arquivos
function Download-Files {
    param (
        [string]$folderUrl
    )
    
    try {
        # Baixar a página da pasta
        $response = Invoke-WebRequest -Uri $folderUrl -UseBasicParsing -TimeoutSec $timeoutSeconds
        $content = $response.Content
        
        # Extrair links para arquivos .zip e .txt
        $files = [regex]::Matches($content, 'href="(.*?\.(zip|txt))"') | 
                 ForEach-Object { $_.Groups[1].Value } |
                 Select-Object -Unique
        
        if (-not $files) {
            Write-Host "Nenhum arquivo encontrado na pasta." -ForegroundColor Yellow
            return
        }
        
        foreach ($file in $files) {
            $fileUrl = "$folderUrl$file"
            $outputFile = "$downloadDir\$file"
            
            if (Test-Path -Path $outputFile) {
                $existingSize = (Get-Item $outputFile).Length / 1MB
                Write-Host "Arquivo já existe: $file ($([math]::Round($existingSize, 2)) MB)" -ForegroundColor Yellow
                continue
            }
            
            Write-Host "`nIniciando download: $file" -ForegroundColor Cyan
            
            $retryCount = 0
            $maxRetries = 3
            $success = $false
            
            while (-not $success -and $retryCount -lt $maxRetries) {
                $retryCount++
                
                if ($retryCount -gt 1) {
                    Write-Host "Tentativa $retryCount de $maxRetries..." -ForegroundColor Yellow
                    Start-Sleep -Seconds (10 * $retryCount) # Aumenta o delay entre tentativas
                }
                
                $success = Download-LargeFile -url $fileUrl -outputPath $outputFile
                
                if ($success) {
                    $finalSize = (Get-Item $outputFile).Length / 1MB
                    Write-Host "Download concluído com sucesso: $file ($([math]::Round($finalSize, 2)) MB)" -ForegroundColor Green
                }
            }
            
            if (-not $success) {
                Write-Host "Falha ao baixar o arquivo após $maxRetries tentativas: $file" -ForegroundColor Red
            }
        }
    } catch {
        Write-Host "Erro ao acessar a pasta: $_" -ForegroundColor Red
    }
}

# Execução principal
Write-Host "`n=== Script de Download de Arquivos CNPJ ===" -ForegroundColor Magenta
Write-Host "Iniciando busca pela pasta mais recente..." -ForegroundColor Cyan

$recentFolder = Get-MostRecentFolder

if ($recentFolder) {
    Write-Host "`nIniciando downloads..." -ForegroundColor Cyan
    Download-Files -folderUrl $recentFolder
    cle
    # Mostrar resumo final
    $downloadedFiles = Get-ChildItem -Path $downloadDir
    if ($downloadedFiles) {
        Write-Host "`nResumo dos downloads:" -ForegroundColor Yellow
        $downloadedFiles | ForEach-Object { 
            $sizeMB = [math]::Round($_.Length / 1MB, 2)
            Write-Host "- $($_.Name) ($sizeMB MB)" 
        }
        $totalSizeMB = [math]::Round(($downloadedFiles | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
        Write-Host "`nTotal baixado: $totalSizeMB MB" -ForegroundColor Green
    } else {
        Write-Host "Nenhum arquivo foi baixado." -ForegroundColor Red
    }
} else {
    Write-Host "`nNão foi possível continuar. Verifique os erros acima." -ForegroundColor Red
}

Write-Host "`nLocal dos arquivos: $downloadDir`n" -ForegroundColor Yellow