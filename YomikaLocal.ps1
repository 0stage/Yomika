param(
    [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'
$script:Port = 1455
$script:BaseUrl = "http://127.0.0.1:$($script:Port)"
$script:OutputRoot = $PSScriptRoot
$script:HtmlPath = Join-Path $PSScriptRoot 'yomika-reader.html'
$script:DataRoot = Join-Path $env:LOCALAPPDATA 'Yomika'
$script:CredentialPath = Join-Path $script:DataRoot 'chatgpt-session.dpapi'
$script:HostIdPath = Join-Path $script:DataRoot 'host-id.txt'
$script:Session = $null
$script:PendingAuth = $null
$script:AuthResult = $null
$script:JwksCache = $null
$script:ModelCache = $null
$script:ModelCacheAt = [DateTime]::MinValue

Add-Type -AssemblyName System.Net.Http

function Get-RandomBase64Url([int]$Length = 32) {
    $bytes = New-Object byte[] $Length
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function ConvertFrom-Base64Url([string]$Value) {
    $s = $Value.Replace('-', '+').Replace('_', '/')
    switch ($s.Length % 4) { 2 { $s += '==' } 3 { $s += '=' } }
    return [Convert]::FromBase64String($s)
}

function ConvertTo-Base64Url([byte[]]$Bytes) {
    return [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function Get-HostId {
    if (Test-Path -LiteralPath $script:HostIdPath) {
        $value = (Get-Content -LiteralPath $script:HostIdPath -Raw).Trim()
        if ($value -match '^urn:uuid:[0-9a-fA-F-]{36}$') { return $value }
    }
    $value = 'urn:uuid:' + [Guid]::NewGuid().ToString()
    [System.IO.File]::WriteAllText($script:HostIdPath, $value, [System.Text.UTF8Encoding]::new($false))
    return $value
}

function Save-Session([object]$Value) {
    if (-not (Test-Path -LiteralPath $script:DataRoot)) {
        New-Item -ItemType Directory -Path $script:DataRoot -Force | Out-Null
    }
    $json = $Value | ConvertTo-Json -Depth 12 -Compress
    $secure = ConvertTo-SecureString -String $json -AsPlainText -Force
    $encrypted = ConvertFrom-SecureString -SecureString $secure
    $temporary = $script:CredentialPath + '.new'
    [System.IO.File]::WriteAllText($temporary, $encrypted, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $script:CredentialPath -Force
    $script:Session = $Value
}

function Load-Session {
    if (-not (Test-Path -LiteralPath $script:CredentialPath)) { return $null }
    try {
        $encrypted = (Get-Content -LiteralPath $script:CredentialPath -Raw).Trim()
        $secure = ConvertTo-SecureString -String $encrypted
        $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try { $json = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
        finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
        return ($json | ConvertFrom-Json)
    } catch {
        Remove-Item -LiteralPath $script:CredentialPath -Force -ErrorAction SilentlyContinue
        return $null
    }
}

function Get-JsonObject([string]$JsonText) {
    if ([string]::IsNullOrWhiteSpace($JsonText)) { return @{} }
    return ($JsonText | ConvertFrom-Json)
}

function Get-QueryValue($Request, [string]$Name) {
    return $Request.QueryString.Get($Name)
}

function Send-Response($Context, [int]$StatusCode, [string]$ContentType, [string]$Body) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
    $Context.Response.StatusCode = $StatusCode
    $Context.Response.ContentType = $ContentType
    $Context.Response.ContentEncoding = [System.Text.Encoding]::UTF8
    $Context.Response.ContentLength64 = $bytes.Length
    $Context.Response.Headers['Cache-Control'] = 'no-store'
    $Context.Response.Headers['X-Content-Type-Options'] = 'nosniff'
    $Context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Context.Response.Close()
}

function Send-Json($Context, [int]$StatusCode, [object]$Value) {
    Send-Response $Context $StatusCode 'application/json; charset=utf-8' ($Value | ConvertTo-Json -Depth 12 -Compress)
}

function Get-RequestBody($Request, [int]$Limit = 50000) {
    if ($Request.ContentLength64 -gt $Limit) { throw 'La solicitud supera el tamaño permitido.' }
    $reader = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
    try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
}

function Assert-SameOrigin($Request) {
    $origin = $Request.Headers['Origin']
    if ($origin -ne $script:BaseUrl) { throw 'Solicitud local no válida. Recarga Yomika desde el lanzador.' }
    if ($Request.Url.Host -ne '127.0.0.1' -or $Request.Url.Port -ne $script:Port) {
        throw 'La solicitud debe usar el origen local de Yomika.'
    }
}

function Get-AuthorizeUrl([bool]$NewAccount) {
    if ($script:PendingAuth -and ((Get-Date) - $script:PendingAuth.created).TotalMinutes -lt 10) {
        throw 'Ya hay un inicio de sesión pendiente. Termínalo en la pestaña de ChatGPT o espera a que caduque.'
    }
    $hostId = Get-HostId
    $state = Get-RandomBase64Url 32
    $nonce = Get-RandomBase64Url 32
    $verifier = Get-RandomBase64Url 48
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $challenge = ConvertTo-Base64Url ($sha.ComputeHash([System.Text.Encoding]::ASCII.GetBytes($verifier))) }
    finally { $sha.Dispose() }
    $clientId = 'dynamic_agent_client'
    $idTokenHint = $null
    $loginHint = $null
    if (-not $NewAccount -and $script:Session -and $script:Session.client_id) {
        $clientId = [string]$script:Session.client_id
        $idTokenHint = [string]$script:Session.id_token
        $loginHint = [string]$script:Session.email
    }
    $script:PendingAuth = [pscustomobject]@{
        created = Get-Date
        state = $state
        nonce = $nonce
        verifier = $verifier
        redirect_uri = "$($script:BaseUrl)/auth/callback"
        client_id = $clientId
        original_subject = $(if ($script:Session -and -not $NewAccount) { [string]$script:Session.subject } else { $null })
    }
    $pairs = [System.Collections.Generic.List[string]]::new()
    $params = [ordered]@{
        client_id = $clientId
        response_type = 'code'
        redirect_uri = $script:PendingAuth.redirect_uri
        scope = 'openid profile email offline_access resource.invoke chatgpt.tokens.use.direct'
        resource = 'https://api.openai.com/v1'
        state = $state
        nonce = $nonce
        code_challenge_method = 'S256'
        code_challenge = $challenge
    }
    if ($clientId -eq 'dynamic_agent_client') {
        $params.agent_name_hint = 'Yomika'
        $params.ext_agent_host_id = $hostId
    } else {
        if ($idTokenHint) { $params.id_token_hint = $idTokenHint }
        if ($loginHint) { $params.login_hint = $loginHint }
    }
    foreach ($key in $params.Keys) { $pairs.Add(([Uri]::EscapeDataString([string]$key) + '=' + [Uri]::EscapeDataString([string]$params[$key]))) }
    return 'https://auth.openai.com/api/accounts/authorize?' + [string]::Join('&', $pairs)
}

function Get-OpenAiHttpClient {
    $client = [System.Net.Http.HttpClient]::new()
    $client.Timeout = [TimeSpan]::FromMinutes(6)
    return $client
}

function Invoke-TokenExchange([hashtable]$Form) {
    $formItems = [System.Collections.Generic.List[System.Collections.Generic.KeyValuePair[string,string]]]::new()
    foreach ($key in $Form.Keys) {
        $formItems.Add([System.Collections.Generic.KeyValuePair[string,string]]::new([string]$key, [string]$Form[$key]))
    }
    $content = [System.Net.Http.FormUrlEncodedContent]::new($formItems)
    $client = Get-OpenAiHttpClient
    try {
        $response = $client.PostAsync('https://auth.openai.com/api/accounts/oauth/token', $content).GetAwaiter().GetResult()
        $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        if (-not $response.IsSuccessStatusCode) {
            $detail = 'No se pudo completar la autorización de ChatGPT (' + [int]$response.StatusCode + ').'
            try { $err = Get-JsonObject $body; if ($err.error_description) { $detail = [string]$err.error_description } elseif ($err.error) { $detail = [string]$err.error } } catch {}
            throw $detail
        }
        return (Get-JsonObject $body)
    } finally { $client.Dispose(); $content.Dispose() }
}

function Get-OpenAiJwks {
    if ($script:JwksCache) { return $script:JwksCache }
    $client = Get-OpenAiHttpClient
    try {
        $raw = $client.GetStringAsync('https://auth.openai.com/.well-known/jwks.json').GetAwaiter().GetResult()
        $script:JwksCache = Get-JsonObject $raw
        return $script:JwksCache
    } finally { $client.Dispose() }
}

function Test-IdToken([string]$Token, [string]$ClientId, [string]$ExpectedNonce) {
    $parts = $Token.Split('.')
    if ($parts.Length -ne 3) { throw 'ChatGPT devolvió un token de identidad no válido.' }
    $header = Get-JsonObject ([System.Text.Encoding]::UTF8.GetString((ConvertFrom-Base64Url $parts[0])))
    $claims = Get-JsonObject ([System.Text.Encoding]::UTF8.GetString((ConvertFrom-Base64Url $parts[1])))
    if ($header.alg -ne 'RS256' -or -not $header.kid) { throw 'El token de identidad usa una firma no admitida.' }
    $jwks = Get-OpenAiJwks
    $key = $jwks.keys | Where-Object { $_.kid -eq $header.kid -and $_.kty -eq 'RSA' } | Select-Object -First 1
    if (-not $key) { $script:JwksCache = $null; $jwks = Get-OpenAiJwks; $key = $jwks.keys | Where-Object { $_.kid -eq $header.kid -and $_.kty -eq 'RSA' } | Select-Object -First 1 }
    if (-not $key) { throw 'No se encontró la clave de firma de ChatGPT.' }
    $rsa = [System.Security.Cryptography.RSA]::Create()
    try {
        $rsaParameters = [System.Security.Cryptography.RSAParameters]::new(); $rsaParameters.Modulus = ConvertFrom-Base64Url ([string]$key.n); $rsaParameters.Exponent = ConvertFrom-Base64Url ([string]$key.e); $rsa.ImportParameters($rsaParameters)
        $signed = [System.Text.Encoding]::ASCII.GetBytes($parts[0] + '.' + $parts[1])
        $signature = ConvertFrom-Base64Url $parts[2]
        if (-not $rsa.VerifyData($signed, $signature, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)) {
            throw 'La firma del token de ChatGPT no es válida.'
        }
    } finally { $rsa.Dispose() }
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $audienceOk = if ($claims.aud -is [Array]) { $claims.aud -contains $ClientId } else { [string]$claims.aud -eq $ClientId }
    if ($claims.iss -ne 'https://auth.openai.com' -or -not $audienceOk -or [long]$claims.exp -le $now -or [string]$claims.nonce -ne $ExpectedNonce -or -not $claims.sub) {
        throw 'La identidad recibida no coincide con la autorización iniciada.'
    }
    return $claims
}

function Complete-Authorization($Request) {
    $pending = $script:PendingAuth
    if (-not $pending -or ((Get-Date) - $pending.created).TotalMinutes -gt 10) { throw 'El inicio de sesión caducó. Vuelve a intentarlo desde Yomika.' }
    $state = Get-QueryValue $Request 'state'
    if (-not $state -or $state -cne $pending.state) { throw 'No se pudo validar el estado de seguridad del inicio de sesión.' }
    $oauthError = Get-QueryValue $Request 'error'
    if ($oauthError) {
        $desc = Get-QueryValue $Request 'error_description'
        if ($oauthError -eq 'access_denied') { throw 'No se concedió a Yomika el permiso para usar el plan de ChatGPT.' }
        $reason = if ($desc) { $desc } else { $oauthError }
        throw ('ChatGPT no autorizó el acceso: ' + $reason)
    }
    $code = Get-QueryValue $Request 'code'
    if (-not $code) { throw 'ChatGPT no devolvió un código de autorización.' }
    $callbackClientId = Get-QueryValue $Request 'client_id'
    if ($pending.client_id -eq 'dynamic_agent_client') {
        if (-not $callbackClientId -or $callbackClientId -eq 'dynamic_agent_client') { throw 'ChatGPT no terminó de registrar la conexión de Yomika.' }
        $issuedClientId = $callbackClientId
    } else {
        if ($callbackClientId -and $callbackClientId -cne $pending.client_id) { throw 'ChatGPT devolvió una cuenta distinta a la seleccionada.' }
        $issuedClientId = $pending.client_id
    }
    $token = Invoke-TokenExchange (@{
        grant_type = 'authorization_code'
        code = $code
        client_id = $issuedClientId
        code_verifier = $pending.verifier
        redirect_uri = $pending.redirect_uri
        resource = 'https://api.openai.com/v1'
    })
    $claims = Test-IdToken ([string]$token.id_token) $issuedClientId $pending.nonce
    if ($pending.original_subject -and [string]$claims.sub -cne [string]$pending.original_subject) { throw 'La cuenta seleccionada no coincide con la cuenta autorizada anteriormente.' }
    $scopes = @(([string]$token.scope -split '\s+') | Where-Object { $_ })
    if ($scopes -notcontains 'chatgpt.tokens.use.direct') { throw 'ChatGPT no concedió el permiso necesario para usar el plan desde Yomika. Revisa los permisos y vuelve a iniciar sesión.' }
    if (-not $token.access_token -or -not $token.refresh_token) { throw 'La sesión no devolvió credenciales renovables.' }
    $script:Session = [pscustomobject]@{
        email = [string]$claims.email
        subject = [string]$claims.sub
        client_id = $issuedClientId
        host_id = Get-HostId
        id_token = [string]$token.id_token
        access_token = [string]$token.access_token
        refresh_token = [string]$token.refresh_token
        token_type = 'Bearer'
        expires_at = [DateTimeOffset]::UtcNow.AddSeconds([int]$token.expires_in).ToUnixTimeSeconds()
        scopes = $scopes
    }
    Save-Session $script:Session
    $script:AuthResult = [pscustomobject]@{ state = 'success'; message = 'La cuenta ChatGPT quedó conectada.'; at = Get-Date }
    $script:PendingAuth = $null
}

function Get-ValidAccessToken {
    if (-not $script:Session) { $script:Session = Load-Session }
    if (-not $script:Session) { throw 'Conecta primero una cuenta de ChatGPT elegible.' }
    if (@($script:Session.scopes) -notcontains 'chatgpt.tokens.use.direct') { throw 'La sesión no tiene permiso para usar el plan de ChatGPT. Desconéctala e inicia sesión de nuevo.' }
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if ([long]$script:Session.expires_at -gt ($now + 120)) { return [string]$script:Session.access_token }
    $refreshed = Invoke-TokenExchange (@{
        grant_type = 'refresh_token'
        refresh_token = [string]$script:Session.refresh_token
        client_id = [string]$script:Session.client_id
        resource = 'https://api.openai.com/v1'
    })
    if (-not $refreshed.access_token -or -not $refreshed.refresh_token) { throw 'ChatGPT no pudo renovar la sesión. Desconecta la cuenta e inicia sesión otra vez.' }
    $script:Session.access_token = [string]$refreshed.access_token
    $script:Session.refresh_token = [string]$refreshed.refresh_token
    $script:Session.expires_at = [DateTimeOffset]::UtcNow.AddSeconds([int]$refreshed.expires_in).ToUnixTimeSeconds()
    if ($refreshed.scope) { $script:Session.scopes = @(([string]$refreshed.scope -split '\s+') | Where-Object { $_ }) }
    Save-Session $script:Session
    return [string]$script:Session.access_token
}

function Get-AvailableModel([string]$AccessToken) {
    if ($script:ModelCache -and ((Get-Date) - $script:ModelCacheAt).TotalMinutes -lt 10) { return $script:ModelCache }
    $client = Get-OpenAiHttpClient
    try {
        $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Get, 'https://api.openai.com/v1/models')
        $request.Headers.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $AccessToken)
        $response = $client.SendAsync($request).GetAwaiter().GetResult()
        $raw = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        if (-not $response.IsSuccessStatusCode) { throw (Get-OpenAiError $raw ([int]$response.StatusCode)) }
        $catalog = Get-JsonObject $raw
        $models = @($catalog.models | Where-Object { $_.visibility -eq 'list' -and $_.slug })
        if (-not $models.Count) { throw 'ChatGPT no devolvió modelos disponibles para esta cuenta.' }
        $best = $models | Where-Object { $_.slug -eq 'gpt-6.1-sol' } | Select-Object -First 1
        if (-not $best) { $best = $models[0] }
        $script:ModelCache = [string]$best.slug
        $script:ModelCacheAt = Get-Date
        return $script:ModelCache
    } finally { $client.Dispose() }
}

function Get-OpenAiError([string]$Body, [int]$StatusCode) {
    try {
        $data = Get-JsonObject $Body
        if ($data.error.message) { return [string]$data.error.message }
        if ($data.error.code -eq 'subscription_sharing_usage_limit_exceeded' -or $data.error.code -eq 'subscription_sharing_usage_unavailable') { return 'ChatGPT no tiene uso del plan disponible en este momento. Revisa sus límites o vuelve a intentarlo más tarde.' }
    } catch {}
    if ($StatusCode -eq 401) { return 'ChatGPT rechazó la sesión. Desconecta la cuenta y vuelve a iniciar sesión.' }
    return "ChatGPT devolvió un error ($StatusCode). Vuelve a intentarlo más tarde."
}

function Invoke-ChatGptResponse([string]$Prompt, [bool]$JsonMode) {
    if ([string]::IsNullOrWhiteSpace($Prompt) -or $Prompt.Length -gt 50000) { throw 'El texto de traducción está vacío o supera el límite local.' }
    $accessToken = Get-ValidAccessToken
    $model = Get-AvailableModel $accessToken
    $payload = @{
        model = $model
        input = @(@{ role = 'user'; content = $Prompt })
        store = $false
        stream = $true
    } | ConvertTo-Json -Depth 8 -Compress
    $content = [System.Net.Http.StringContent]::new($payload, [System.Text.Encoding]::UTF8, 'application/json')
    $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Post, 'https://api.openai.com/v1/responses')
    $request.Headers.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $accessToken)
    $request.Headers.Accept.ParseAdd('text/event-stream')
    $request.Content = $content
    $client = Get-OpenAiHttpClient
    $builder = [System.Text.StringBuilder]::new()
    $completed = $false
    try {
        $response = $client.SendAsync($request, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        if (-not $response.IsSuccessStatusCode) {
            $raw = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            throw (Get-OpenAiError $raw ([int]$response.StatusCode))
        }
        $stream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8)
        try {
            while (-not $reader.EndOfStream) {
                $line = $reader.ReadLine()
                if (-not $line.StartsWith('data: ')) { continue }
                $dataText = $line.Substring(6)
                if ($dataText -eq '[DONE]') { continue }
                try { $event = Get-JsonObject $dataText } catch { continue }
                switch ([string]$event.type) {
                    'response.output_text.delta' { [void]$builder.Append([string]$event.delta) }
                    'response.completed' { $completed = $true }
                    'response.failed' {
                        $failure = $event.response.error
                        if ($failure.code -in @('subscription_sharing_usage_limit_exceeded','subscription_sharing_usage_unavailable')) { throw 'ChatGPT no tiene uso del plan disponible en este momento. Revisa sus límites o vuelve a intentarlo más tarde.' }
                        if ($failure.message) { throw [string]$failure.message }
                        throw 'ChatGPT no pudo completar la traducción.'
                    }
                    'error' { throw (Get-OpenAiError ($dataText) 400) }
                }
            }
        } finally { $reader.Dispose() }
        if (-not $completed) { throw 'La respuesta de ChatGPT se interrumpió antes de terminar. Inténtalo de nuevo.' }
        $text = $builder.ToString().Trim()
        if (-not $text) { throw 'ChatGPT no devolvió texto.' }
        return $text
    } finally { $client.Dispose(); $content.Dispose(); $request.Dispose() }
}

function Handle-Context($Context) {
    $request = $Context.Request
    $path = $request.Url.AbsolutePath
    try {
        if ($request.Url.Host -ne '127.0.0.1' -or $request.Url.Port -ne $script:Port) { Send-Json $Context 403 @{ error = 'Origen local no válido.' }; return }
        if ($request.HttpMethod -eq 'GET' -and ($path -eq '/' -or $path -eq '/yomika-reader.html')) {
            if (-not (Test-Path -LiteralPath $script:HtmlPath)) { Send-Response $Context 404 'text/plain; charset=utf-8' 'No se encontró yomika-reader.html junto al lanzador.'; return }
            $html = [System.IO.File]::ReadAllText($script:HtmlPath)
            Send-Response $Context 200 'text/html; charset=utf-8' $html
            return
        }
        if ($request.HttpMethod -eq 'GET' -and $path -eq '/auth/callback') {
            try {
                Complete-Authorization $request
                $page = '<!doctype html><meta charset="utf-8"><title>Yomika conectado</title><style>body{font:16px system-ui;background:#f4ecd9;color:#423528;display:grid;place-items:center;min-height:90vh}main{background:white;padding:32px;border-radius:18px;box-shadow:0 10px 32px #0002;max-width:480px}h1{margin-top:0}</style><main><h1>Yomika ya está conectado</h1><p>La cuenta ChatGPT quedó conectada. Puedes volver a la pestaña de Yomika.</p></main>'
                Send-Response $Context 200 'text/html; charset=utf-8' $page
            } catch {
                $script:AuthResult = [pscustomobject]@{ state = 'error'; message = $_.Exception.Message; at = Get-Date }
                $script:PendingAuth = $null
                $safe = [System.Net.WebUtility]::HtmlEncode($_.Exception.Message)
                $page = '<!doctype html><meta charset="utf-8"><title>Error de acceso</title><style>body{font:16px system-ui;background:#f4ecd9;color:#423528;display:grid;place-items:center;min-height:90vh}main{background:white;padding:32px;border-radius:18px;box-shadow:0 10px 32px #0002;max-width:480px}h1{margin-top:0}</style><main><h1>No se pudo conectar</h1><p>' + $safe + '</p><p>Vuelve a Yomika para intentarlo otra vez.</p></main>'
                Send-Response $Context 400 'text/html; charset=utf-8' $page
            }
            return
        }
        if ($request.HttpMethod -eq 'GET' -and $path -eq '/api/chatgpt/status') {
            if (-not $script:Session) { $script:Session = Load-Session }
            $connected = [bool]$script:Session
            $plan = $connected -and (@($script:Session.scopes) -contains 'chatgpt.tokens.use.direct')
            $message = if ($plan) { 'Cuenta conectada; uso del plan autorizado por ChatGPT.' } elseif ($connected) { 'La cuenta está conectada, pero ChatGPT no concedió el permiso de uso del plan.' } else { 'Conecta una cuenta ChatGPT que tenga habilitado el uso del plan para esta función.' }
            $email = if ($connected) { [string]$script:Session.email } else { '' }; Send-Json $Context 200 @{ connected = $connected; planUsage = [bool]$plan; email = $email; message = $message; authResult = $script:AuthResult }
            return
        }
        if ($request.HttpMethod -eq 'POST' -and $path -eq '/api/chatgpt/authorize') {
            Assert-SameOrigin $request
            $body = Get-JsonObject (Get-RequestBody $request 20000)
            $url = Get-AuthorizeUrl ([bool]$body.newAccount)
            $script:AuthResult = $null
            Send-Json $Context 200 @{ url = $url }
            return
        }
        if ($request.HttpMethod -eq 'POST' -and $path -eq '/api/chatgpt/logout') {
            Assert-SameOrigin $request
            if (Test-Path -LiteralPath $script:CredentialPath) { Remove-Item -LiteralPath $script:CredentialPath -Force }
            $script:Session = $null
            $script:ModelCache = $null
            Send-Json $Context 200 @{ revoked = $false }
            return
        }
        if ($request.HttpMethod -eq 'POST' -and $path -eq '/api/chatgpt/responses') {
            Assert-SameOrigin $request
            $body = Get-JsonObject (Get-RequestBody $request 70000)
            $text = Invoke-ChatGptResponse ([string]$body.prompt) ([bool]$body.json)
            Send-Json $Context 200 @{ text = $text }
            return
        }
        Send-Json $Context 404 @{ error = 'Ruta no encontrada.' }
    } catch {
        Send-Json $Context 400 @{ error = $_.Exception.Message }
    }
}

if (-not (Test-Path -LiteralPath $script:HtmlPath)) {
    Write-Host 'No se encontró outputs\yomika-reader.html.' -ForegroundColor Red
    exit 1
}
if (-not (Test-Path -LiteralPath $script:DataRoot)) { New-Item -ItemType Directory -Path $script:DataRoot -Force | Out-Null }
$script:Session = Load-Session
$listener = $null
$firstPort = 1455
$lastPort = 1470
for ($candidatePort = $firstPort; $candidatePort -le $lastPort; $candidatePort++) {
    $candidate = [System.Net.HttpListener]::new()
    $candidate.Prefixes.Add("http://127.0.0.1:$candidatePort/")
    try {
        $candidate.Start()
        $listener = $candidate
        $script:Port = $candidatePort
        $script:BaseUrl = "http://127.0.0.1:$candidatePort"
        break
    } catch {
        try { $candidate.Close() } catch {}
    }
}
if (-not $listener) {
    Write-Host "No hay un puerto local disponible entre $firstPort y $lastPort. Cierra alguna instancia de Yomika u otra aplicación que los esté usando." -ForegroundColor Red
    exit 1
}
if ($script:Port -ne $firstPort) {
    Write-Host "El puerto $firstPort estaba ocupado; Yomika usará el puerto $($script:Port)." -ForegroundColor Yellow
}
Write-Host "Yomika está listo en $($script:BaseUrl)" -ForegroundColor Green
Write-Host 'La sesión de ChatGPT se guarda cifrada para tu usuario de Windows. Cierra esta ventana para detener Yomika.'
if (-not $NoBrowser) { Start-Process $script:BaseUrl }
try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        Handle-Context $context
    }
} finally {
    $listener.Stop()
    $listener.Close()
}