# download-cnpj-RFB
Script em PowerShell para download dos arquivos .zip de CNPJs disponivel em dados abertos da RFB.

Como executar:

Faça download do arquivo e salve na unidade C, após abra o PowerShell como administrador e cole o comando:

Set-ExecutionPolicy RemoteSigned -Scope Process -Force
.\Download_CNPJ.ps1

O Script criará uma pasta no disco C:\Downloads_CNPJ e salvará todos os arquivos encontrados.
