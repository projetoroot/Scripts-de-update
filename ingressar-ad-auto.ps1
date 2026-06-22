######################################################################################
# SCRIPT DE INGRESSO AUTOMÁTICO NO ACTIVE DIRECTORY                                  #
# Autor: Diego Costa (@diegocostaroot) / Projeto Root (youtube.com/projetoroot)      #
# Versão: 1.0                                                                        #
# Veja o link: https://github.com/projetoroot                                        #
# 2026                                                                               #
# Executar o Powershell como Administrador                                           #
# Entrar na pasta que fez o download e executar .\ingressar-ad-auto.ps1              #
# Após a execução é extremamente necessário reiniciar.                               #
#                                                                                    #
# Testado em: Windows 10 22H2+, Windows 11, Windows Server 2016+                     #
# Objetivo: Ingressar de maneira automática estações de trabalho no AD da empresa    #
#         de forma remota sem a necessidade de estar presencial na frente máquina.   #
######################################################################################


# ==========================================================
# AUTOELEVAÇÃO COMPATÍVEL COM EXECUÇÃO VIA SMB
# ==========================================================
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent()
)

if (-not $currentPrincipal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)) {

    Write-Host ""
    Write-Host "Solicitando permissões administrativas..."

    $OriginalScript = $MyInvocation.MyCommand.Path
    $LocalScript = Join-Path $env:TEMP "ingressar-ad-auto.ps1"

    Copy-Item -Path $OriginalScript -Destination $LocalScript -Force

    Start-Process powershell.exe `
        -Verb RunAs `
        -ArgumentList "-ExecutionPolicy Bypass -NoExit -File `"$LocalScript`""

    exit
}

# ==========================================================
# ENTRADAS
# ==========================================================
Write-Host ""
Write-Host "=== CONFIGURAÇÃO DO INGRESSO NO DOMÍNIO ==="
Write-Host ""

$DomainName = Read-Host "Digite o dominio (ex: ad.empresa.com.br)"
$PrimaryDNS = Read-Host "Digite o DNS primario IP dns do AD - (ex: 10.10.10.1)"
$SecondaryDNS = Read-Host "Digite o DNS secundario IP dns do AD - (ex: 10.10.10.2)"
$NewComputerName = Read-Host "Digite o nome da maquina (ex: EMPRESA-123456)"
$DisableIPv6 = Read-Host "Deseja desativar IPv6? (S/N)"

# ==========================================================
# VALIDAÇÕES
# ==========================================================
if ([string]::IsNullOrWhiteSpace($DomainName)) {
    Write-Host "Domínio inválido."
    pause
    exit
}

if (-not [System.Net.IPAddress]::TryParse($PrimaryDNS, [ref]$null)) {
    Write-Host "DNS primário inválido."
    pause
    exit
}

if (-not [System.Net.IPAddress]::TryParse($SecondaryDNS, [ref]$null)) {
    Write-Host "DNS secundário inválido."
    pause
    exit
}

if ([string]::IsNullOrWhiteSpace($NewComputerName)) {
    Write-Host "Nome da máquina inválido."
    pause
    exit
}

if ($NewComputerName.Length -gt 15) {
    Write-Host "O nome da maquina deve ter no maximo 15 caracteres."
    pause
    exit
}

try {

    # ==========================================================
    # LOCALIZA INTERFACES FÍSICAS ATIVAS
    # ==========================================================
    Write-Host ""
    Write-Host "Localizando interfaces ativas..."

    $Adapters = Get-NetAdapter | Where-Object {
        $_.Status -eq "Up" -and $_.HardwareInterface -eq $true
    }

    if (!$Adapters) {
        Write-Host "Nenhuma interface ativa encontrada."
        pause
        exit
    }

    foreach ($Adapter in $Adapters) {

        # ==========================================================
        # DESATIVA IPV6
        # ==========================================================
        if ($DisableIPv6 -match "^[Ss]$") {

            Write-Host "Desativando IPv6 em $($Adapter.Name)..."

            $IPv6Binding = Get-NetAdapterBinding `
                -Name $Adapter.Name `
                -ComponentID ms_tcpip6 `
                -ErrorAction SilentlyContinue

            if ($IPv6Binding -and $IPv6Binding.Enabled) {
                Disable-NetAdapterBinding `
                    -Name $Adapter.Name `
                    -ComponentID ms_tcpip6 `
                    -Confirm:$false
            }
        }

        # ==========================================================
        # CONFIGURA DNS
        # ==========================================================
        Write-Host "Configurando DNS em $($Adapter.Name)..."

        Set-DnsClientServerAddress `
            -InterfaceIndex $Adapter.ifIndex `
            -ServerAddresses ($PrimaryDNS, $SecondaryDNS)
    }

    # ==========================================================
    # DESATIVA IPV6 GLOBALMENTE
    # ==========================================================
    if ($DisableIPv6 -match "^[Ss]$") {

        Write-Host "Aplicando desativacao global do IPv6..."

        New-ItemProperty `
            -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" `
            -Name "DisabledComponents" `
            -PropertyType DWord `
            -Value 255 `
            -Force | Out-Null
    }

    # ==========================================================
    # LIMPA CACHE DNS
    # ==========================================================
    Write-Host "Limpando cache DNS..."
    ipconfig /flushdns | Out-Null

    # ==========================================================
    # TESTA DNS DO DOMÍNIO
    # ==========================================================
    Write-Host "Validando resolucao do dominio..."

    Resolve-DnsName `
        -Name $DomainName `
        -Type A `
        -Server $PrimaryDNS `
        -ErrorAction Stop | Out-Null

    # ==========================================================
    # TESTA SRV LDAP
    # ==========================================================
    Write-Host "Validando registros LDAP..."

    Resolve-DnsName `
        -Name "_ldap._tcp.dc._msdcs.$DomainName" `
        -Type SRV `
        -Server $PrimaryDNS `
        -ErrorAction Stop | Out-Null

    # ==========================================================
    # CREDENCIAIS
    # ==========================================================
    Write-Host ""
    $Credential = Get-Credential -Message "Informe usuario e senha com permissao para ingressar no dominio"

    # ==========================================================
    # RENOMEIA HOST
    # ==========================================================
    $CurrentName = $env:COMPUTERNAME

    if ($CurrentName -ne $NewComputerName) {

        Write-Host "Renomeando computador de $CurrentName para $NewComputerName..."

        Rename-Computer `
            -NewName $NewComputerName `
            -Force `
            -ErrorAction Stop
    }

    # ==========================================================
    # INGRESSA NO DOMÍNIO
    # ==========================================================
    Write-Host "Ingressando no dominio..."

    Add-Computer `
        -DomainName $DomainName `
        -Credential $Credential `
        -Options JoinWithNewName,AccountCreate `
        -Force `
        -ErrorAction Stop

    # ==========================================================
    # REGISTRA NO DNS
    # ==========================================================
    Write-Host "Registrando host no DNS..."
    ipconfig /registerdns | Out-Null

    # ==========================================================
    # FINALIZA
    # ==========================================================
    Write-Host ""
    Write-Host "Maquina ingressada com sucesso."
    Write-Host "Reiniciando em 10 segundos..."

    Start-Sleep -Seconds 10
    Restart-Computer -Force
}
catch {
    Write-Host ""
    Write-Host "Erro encontrado:"
    Write-Host $_.Exception.Message
    pause
}
