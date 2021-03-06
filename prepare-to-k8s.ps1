param(
    [string] $s,            # Solution path
    [string] $p,            # Main application project path
    [string] $h,            # Helm project/chart path
    [switch] $f,            # Overwrites files without confirmation (force)
    [int16]  $port,         # Port number of the external endpoint of the serivce
    [string] $liveness,     # Configure liveness probe URL, timeout, retries and interval
    [string] $readiness,    # Configure readiness probe URL, timeout, retries and initial delay
    [string] $maxcpu,       # Limits CPU usage for the pod
    [string] $maxmem,       # Limits memory usage for the pod
    [string] $mincpu,       # Require this free CPU to schedule pod in a node
    [string] $minmem,       # Require this free memory to schedule pod in a node
    [string] $url,          # External URL template
    [switch] $http,         # Configures service for HTTP access (if omitted, configures HTTPS)
    [string] $certificate,  # Certificate name (as installed in F5 partition)

    [alias("v")]
    [switch] $verbose,      # Outputs all created/modified files content
    [switch] $help,         # Displays quick help about the script
    [switch] $stable,       # Disable all temporary/experimental changes
    [switch] $minikube      # Configure solution to run on Minikube instead of K8s Cluster
)

set-executionpolicy remotesigned -s cu
$ErrorActionPreference = "Stop"



# Constants
$base_namespace     = 'MyDomain.MyNamespace'
$mainproj_suffix    = 'Api'
$jenkins_version    = "{JENKINS_VERSION}"               # CHANGE HERE!
$jenkins_namespace  = 'com.mydomain.jenkins.jobs'       # CHANGE HERE!
$docker_registry    = "docker-registry.mydomain:port"   # CHANGE HERE!
$docker_feed        = ""
$kafka_group_suffix = '-k8s'
$secret_db_user     = 'DB_USER'
$secret_db_pwd      = 'DB_PASSWORD'
$env_db_user        = "K8S_$secret_db_user"
$env_db_pwd         = "K8S_$secret_db_pwd"
$tag_db_user        = "{$secret_db_user}"
$tag_db_pwd         = "{$secret_db_pwd}"
$tag_connstr        = "User Id=$tag_db_user;Password=$tag_db_pwd"

$dns_dev_ip      = "10.251.149.21"  # CHANGE HERE!
$dns_tst_ip      = "10.251.149.21"  # CHANGE HERE!
$dns_acc_ip      = "10.251.149.22"  # CHANGE HERE!
$dns_prd_ip      = "10.251.149.23"  # CHANGE HERE!

$f5_dev_part     = "K8s"
$f5_tst_part     = "K8s"
$f5_acc_part     = "K8s-acc"
$f5_prd_part     = "K8s"

$default_port       = 80

$unknown            = '??????'

# Default values
$dotnet_image = 'aspnetcore@sha256:5f964756fae50873c496915ad952b0f15df8ef985e4ac031d00b7ac0786162d0' #default (netcore 2.0)

$probe_live_url     = '/info'
$probe_live_period  = 10
$probe_live_timeout = 5
$probe_live_retries = 3
$probe_ready_url    = '/hc'
$probe_ready_delay  = 10
$probe_ready_timeout= 10
$probe_ready_retries= 3

$ext_url_template   = "svc-{ALIAS}.api.{ENV}-mydomain.com"  # CHANGE HERE!

if (!$certificate) { $certificate = "/Common/clientssl" }   # CHANGE HERE!

# The const bellow is used to highlight temporary/experimental blocks in conversion script
# As soon as the changes are not needed anymore or they become permanent, it's easier to search
# for it and locate the blocks to be modified or removed. Changing its value to 0 also easily
# disable all those blocks at once.
$xp_blocks          = $false #(-not $stable)

if ($liveness) {
    $liveness = $liveness.Split(',')
    $i = $liveness.GetUpperBound(0)
    $probe_live_url = $liveness[0]
    if ($i -gt 0) { $probe_live_period  = $liveness[1] }
    if ($i -gt 1) { $probe_live_timeout = $liveness[2] }
    if ($i -gt 2) { $probe_live_retries = $liveness[3] }
}

if ($readiness) {
    $readiness = $readiness.Split(',')
    $i = $readiness.GetUpperBound(0)
    $probe_ready_url = $readiness[0]
    if ($i -gt 0) { $probe_ready_delay   = $readiness[1] }
    if ($i -gt 1) { $probe_ready_timeout = $readiness[2] }
    if ($i -gt 2) { $probe_ready_retries = $readiness[3] }
}



Write-Host ''
Write-Host ''
Write-Host ''
Write-Host 'Automated Configuration Script for Kubernetes deploy' -ForegroundColor Cyan
Write-Host ''

if ($help) # Sorry MS, but Get-Help method sucks...
{
    Write-Host 'DESCRIPTION' -ForegroundColor DarkGray
    Write-Host 'Prepares a .NET Core application to be deployed into Kubernetes cluster through Helm.'
    Write-Host ''
    Write-Host 'USAGE' -ForegroundColor DarkGray
    Write-Host ($MyInvocation.MyCommand.Name) "[[parameter value] | [parameter]]"
    Write-Host ''
    Write-Host 'PARAMETERS' -ForegroundColor DarkGray
    Write-Host '-s <path>       Solution file path. If omited the script needs to run in the solution folder.'
    Write-Host '-p <path>       Project file path. If omited the script prompts the user for it.'
    Write-Host '-h <name>       Helm project name. If omited the script prompts the user for it.'
    Write-Host '-port           Port number of the external endpoint of the service. If omitted, uses value in "hosting.json"'
    Write-Host '-f              Force the overwriting of all files without confirmation.'
    Write-Host '-readiness      Set readiness probe configuration in the format "<url>[,<delay>[,<timeout>[,<retries>]]]".'
    Write-Host '-liveness       Set liveness probe configuration in the format "<url>[,<interval>[,<timeout>[,<retries>]]]".'
    Write-Host '-maxcpu         Limits CPU cores usage for the pod. Ex: 1.5 or 1500m limits usage to 1.5 cores.'
    Write-Host '-maxmem         Limits memory usage for the pod, in bytes. Ex: 2147483648 = 2000Mi = 2Gi'
    Write-Host '-mincpu         Require this free CPU to schedule pod in a node. This can avoid pod from being started.'
    Write-Host '-minmem         Require this free memory to schedule pod in a node. This can avoid pod from being started.'
    Write-Host "-url, -u        External URL. Inform service alias only of full URL with {ENV} as placeholder for environment code. Ex: $ext_url_template"
    Write-Host "-http           Indicates that service is to be configured for HTTP access (configures HTTPS if omitted)"
    Write-Host "-certificate    Certificate name (as installed in F5 partition)"

    Write-Host '-minikube       Prepare the application to deploy in local Kubernetes cluster (Minikube).'
    Write-Host '-verbose, -v    Show the content of all modified/created files.'
    Write-Host '-stable         Disable all temporary/experimental changes made by the script'
    Write-Host '-help, -h       Prints info about the script anf list of parameters.'
    Write-Host ''

    exit
}

if ($verbose)
{
    Write-Host 'Running in VERBOSE MODE!' -ForegroundColor DarkYellow
    Write-Host ''
}


#
# Validations
#
# Check if Helm is installed
if ($null -eq (Get-Command "helm.exe" -ErrorAction SilentlyContinue))
{
   Write-Host 'Helm is not properly installed on this machine: "helm.exe" not found in the system path.' -ForegroundColor Red
   exit
}




#
# Get script data
#

# Solution file
if ('' -eq $s)
{
    $solution = [System.IO.FileInfo] (@(Get-ChildItem *.sln)[0])

    if ($null -eq $solution)
    {
        Write-Host 'Solution file not found. Run this script in a valid solution folder or use -s to specify a solution file.' -ForegroundColor Red
        exit
    }

    Write-Host 'Solution "' -NoNewline
    Write-Host $solution.Name -ForegroundColor Cyan -NoNewline
    Write-Host '" found in the current directory.'
    Write-Host ''
}
else
{
    $solution = [System.IO.FileInfo] (Get-ChildItem $s)

    if ($null -eq $solution)
    {
        Write-Host "Solution file '$solution' not found." -ForegroundColor Red
        exit
    }
}

$solution_dir = $solution.Directory.FullName
Set-Location $solution_dir


# Helm project/chart name
if ('' -eq $h)
{
    Write-Host ('Please enter Helm project/chart name. ' +
    'It is recommended to use the form <project>-<application> (e.g. rivdec-associations). ' +
    'This information will also be used to create the Docker image and configure Jenkins file.')

    Write-Host $solution.BaseName
    if ($solution.BaseName -match '([\w]*?)\.([\w]*?)$')
    {
        $helm_project = ($Matches[1] + '-' + $Matches[2]).ToLower()
        Write-Host '(Leave it blank to use the suggested name "' -NoNewline -ForegroundColor DarkGray
        Write-Host $helm_project -NoNewline -ForegroundColor DarkGray
        Write-Host '")' -ForegroundColor DarkGray
    }

    $op = Read-Host "Helm Project"
    Write-Host ''

    if ($op)
    {
        $helm_project = $op.ToLower()
    }
}
else
{
    $helm_project = $h.ToLower()
}

if ($helm_project -eq '')
{
    Write-Host "No Helm project/chart name defined. Operation canceled." -ForegroundColor Red
    Exit
}

# Application project file
if ('' -eq $p)
{
    # Select the entrypoint application
    Write-Host "Available projects:"
    $files_found = @(Get-ChildItem *.csproj -Recurse)

    if ($files_found.Length -eq 0)
    {
        Write-Host "Folder $solution_dir does not have .csproj fies." -ForegroundColor Red
        exit
    }

    $op = 1
    foreach($proj in $files_found)
    {
        Write-Host '  ' $op ': ' -NoNewline -ForegroundColor Cyan
        Write-Host $proj.BaseName
        $op = $op + 1
    }
    Write-Output ''
    $op = Read-Host "Please choose the APPLICATION project"
    $main_proj = [System.IO.FileInfo]$files_found[$op - 1]
    Write-Host ''

}
else
{
    $main_proj = [System.IO.FileInfo] (Get-ChildItem $p)
}

if ($null -eq $main_proj)
{
    Write-Host 'Invalid option!' -ForegroundColor Red
    Exit
}


# Check main project .NET Core version
$dotnet_version = $false

$content = $(Get-Content $main_proj.FullName -Raw)
if ($content -match "<TargetFramework>netcoreapp(.*?)<") {
    $dotnet_version = $Matches[1]
}
else {
    # If TargetFramework is not found, look for an imported csproj
    if ($content -match '<Import Project="(.*?)"') {
        $file = $main_proj.Directory.FullName + "\" + $Matches[1]
        $content = $(Get-Content $file -Raw)
        if ($content -match "<TargetFramework>netcoreapp(.*?)<") {
            $dotnet_version = $Matches[1]
        }
    }
}

if (!$dotnet_version) {
    Write-Error "$($main_proj.BaseName) does not seem to be a valid .NET Core project: expected <TargetFramework>netcoreappXXX</TargetFramework>."
    Exit;
}
else {
    if ($dotnet_version -le 2.0) {
        $dotnet_image = "aspnetcore:"
    }
    else {
        $dotnet_image = "dotnet:"
    }
    $dotnet_image += "$dotnet_version-aspnetcore-runtime"
}


$docker_repo, $docker_img = $helm_project.Split('-')
$docker_img_full = ''
($docker_registry, $docker_feed, $docker_repo, $docker_img) | ForEach-Object {
    if (-not [string]::IsNullOrEmpty($_)) {
        $docker_img_full += $_.trim('/') + '/'
    }
}
$docker_img_full = $docker_img_full.trim('/')

# Check external endpoint port number
if (-not $port)
{
    $file = $main_proj.Directory.FullName + '\hosting.json'
    if (Test-Path $file)
    {
        $content = (Get-Content ($file) -Raw)
        if ($content -match '"?urls"?\s*:\s*".*?([0-9]+)"')
        {
            $port = [int16] $Matches[1]
        }
        else
        {
            $port = $default_port
        }
    }
    else
    {
        $port = $default_port
    }
}


if ($minikube) {
    $docker_registry = 'proget_test'

    $file = "$solution_dir\helm\$helm_project\Chart.yaml"
    $jenkins_version = '0.1'
    if (Test-Path $file) {
        $content = (Get-Content $file -Raw)
        if ($content -match '\sversion:\s*([0-9]+)\.?([0-9]*)') {
            $op = $Matches[1] + '.' + [string]([int32]$Matches[2] + 1)
        }
    }

    $op = Read-Host "Please inform Chart/Docker image version (press ENTER to accept $jenkins_version):"

    if ('' -ne $op) {
        $jenkins_version = $op
    }

    Write-Host ''
}

# Configure external URL (load balancer)
if (!$url) {
    Write-Host 'Inform service alias or the full URL for external load balancer. For full URL, use {ENV} as placeholder for environment code.'
    Write-Host "[press Enter to use default '$ext_url_template']" -NoNewline -ForegroundColor DarkGray
    $op = Read-Host ' '
    if ($op) { $url = $op }
    Write-Host ''
}

if ($url) {
    if ($url.EndsWith('.be')) {     # full URL template
        $ext_url_template = $url
    }

    else {      # Only alias
        $ext_url_template = ($ext_url_template -replace '{ALIAS}',$url)
    }
}
else {
    $ext_url_template = ($ext_url_template -replace '{ALIAS}',$unknown)
}

# Configure READINESS and LIVENESS probe
if (!$readiness -and ((Read-Host -Prompt "Do you want to configure probe settings? [y/n]") -match '[yY]'))
{
    Write-Host ''
    Write-Host 'REDINESS PROBE:' -ForegroundColor Yellow
    Write-Host ''

    Write-Host '  Inform the URL used for readiness check ' -NoNewline
    Write-Host "  [press Enter to use default '$probe_ready_url']" -NoNewline -ForegroundColor DarkGray
    $op = Read-Host ' '
    if ($op) { $probe_ready_url = $op }

    Write-Host '  Inform the initial delay (seconds) before checking for readiness ' -NoNewline
    Write-Host "  [press Enter to use default $probe_ready_delay]" -NoNewline -ForegroundColor DarkGray
    $op = Read-Host ' '
    if ($op) { $probe_ready_delay = [int]$op }

    Write-Host '  Inform a timeout (seconds) to wait for a response ' -NoNewline
    Write-Host "  [press Enter to use default $probe_ready_timeout]" -NoNewline -ForegroundColor DarkGray
    $op = Read-Host ' '
    if ($op) { $probe_ready_timeout = [int]$op }

    Write-Host '  Inform the number of times the probe will try to check for readiness ' -NoNewline
    Write-Host "  [press Enter to use default $probe_ready_retries]" -NoNewline -ForegroundColor DarkGray
    $op = Read-Host ' '
    if ($op) { $probe_ready_retries = [int]$op }

    Write-Host ''
    Write-Host ''
    Write-Host 'LIVENESS PROBE:' -ForegroundColor Yellow
    Write-Host ''

    Write-Host '  Inform the URL used for liveness check ' -NoNewline
    Write-Host "  [press Enter to use default '$probe_live_url']" -NoNewline -ForegroundColor DarkGray
    $op = Read-Host ' '
    if ($op) { $probe_live_url = $op }

    Write-Host '  Inform the interval (seconds) between each liveness checking ' -NoNewline
    Write-Host "  [press Enter to use default $probe_live_period]" -NoNewline -ForegroundColor DarkGray
    $op = Read-Host ' '
    if ($op) { $probe_live_period = [int]$op }

    Write-Host '  Inform a timeout (seconds) to wait for a response ' -NoNewline
    Write-Host "  [press Enter to use default $probe_live_timeout]" -NoNewline -ForegroundColor DarkGray
    $op = Read-Host ' '
    if ($op) { $probe_live_timeout = [int]$op }

    Write-Host '  Inform the number of times the probe will try to check for liveness ' -NoNewline
    Write-Host "  [press Enter to use default $probe_live_retries]" -NoNewline -ForegroundColor DarkGray
    $op = Read-Host ' '
    if ($op) { $probe_live_retries = [int]$op }

    Write-Host ''
}



#
# Summary
#
Write-Host ''
Write-Host 'The solution is about to be configured to deploy and run in the Kubernetes cluster.'
Write-Host ('During the process the name of all created/modified files will be printed. Please check the files before deploying. ' +
            'Moreover, as some settings depend on each application, a TODO list will be presented at the end. ' +
            'Follow these steps to complete the configuration.')
Write-Host ''

Write-Host 'Helm Project:          ' -NoNewline
Write-Host $helm_project -ForegroundColor Yellow
Write-Host 'Solution File:         ' -NoNewline
Write-Host $solution.Name -ForegroundColor Yellow
Write-Host 'Project File:          ' -NoNewline
Write-Host $main_proj.Name -ForegroundColor Yellow
Write-Host '.NET Core version:     ' -NoNewline
Write-Host $dotnet_version -ForegroundColor Yellow
Write-Host 'Service Port:          ' -NoNewline
Write-Host $port -ForegroundColor Yellow
Write-Host 'Readiness Probe:       ' -NoNewline
Write-Host "+$probe_ready_url delay=${probe_ready_delay}s timeout=${probe_ready_timeout}s retries=${probe_ready_retries}" -ForegroundColor Yellow
Write-Host 'Liveness Probe:        ' -NoNewline
Write-Host "+$probe_live_url period=${probe_live_period}s timeout=${probe_live_timeout}s retries=${probe_live_retries}" -ForegroundColor Yellow
Write-Host 'Resource Limits:       ' -NoNewline
Write-Host "cpu=${maxcpu} memory=${maxmem}" -ForegroundColor Yellow
Write-Host 'Resource Requirements: ' -NoNewline
Write-Host "cpu=${mincpu} memory=${minmem}" -ForegroundColor Yellow
Write-Host 'External URL:          ' -NoNewline
Write-Host $ext_url_template -ForegroundColor Yellow

if ($minikube) {
    Write-Host 'Image/Chart version:  ' -NoNewline
    Write-Host $port -ForegroundColor Yellow
}

Write-Host ''

$op = Read-Host -Prompt "Confirm informations and continue? [y/n]"
if ($op -match '[^yY]')
{
    Write-Host ''
    Write-Host 'Operation cancelled.' -ForegroundColor Red
    Exit
}
Write-Host ''






#
# HELM
#
Write-Output ''
Write-Host 'PREPARING HELM  -----------------------------------------------------------------------' -ForegroundColor Cyan

# Create project
if (Test-Path "$solution_dir\helm")
{
    Write-Host "  There's already a Helm project with this name in the Solution. All files will be ERASED and recreated." -ForegroundColor Yellow
    if ($f)
    {
        $overwrite = "y"
    }
    else
    {
        $overwrite = Read-Host -Prompt "  Continue? [y/n]"
    }
    Write-Host ''
    if ( $overwrite -match "[yY]" )
    {
        Write-Host '  Removing old Helm project... ' -NoNewline
        Remove-Item -path .\helm -Recurse > $null
        Write-Host 'Ok!' -ForegroundColor DarkGreen
        Write-Host ''
    }
    else
    {
        Write-Host 'Operation cancelled. Have a nice day :)'
        Exit
    }
}

mkdir helm > $null
Set-Location .\helm > $null

Write-Host "  - Creating Helm project... " -NoNewline

helm create $helm_project > $null
Set-Location $helm_project > $null
mkdir external > $null

$helm_dir = $solution_dir + '\helm\' + $helm_project
Write-Host $helm_dir -ForegroundColor DarkGreen
Set-Location $solution_dir > $null

# Configuring Chart.yaml
Write-Host '  - Configuring Helm files...'
$file = "$helm_dir\Chart.yaml"
$tmp = ($solution.BaseName -replace "$base_namespace.",'') -replace ".$mainproj_suffix",''  # PROBABLY CHAGE HERE TOO
$content = ((Get-Content $file) `
    -replace '^description:.*',"description: Helm chart for the RIVDEC $tmp microservice" `
    -replace '^version:.*',"version: $jenkins_version" -join "`r`n")

$content | Set-Content $file -Encoding Default

Write-Host "    : $file" -ForegroundColor DarkGreen
if ($verbose) { Write-Host $content -ForegroundColor DarkGray }

# Configuring values.yaml
$file = "$helm_dir\values.yaml"

$content = (Get-Content $file -Raw) `
    -replace '  tag: stable',"  tag: $jenkins_version" `
    -replace '  repository:.*',"  repository: $docker_img_full" `
    -replace '  port: 80',"  port: $port" `

if (!$minikube) {
    $annotations = ("annotations:`r`n" +
                    "  kubernetes.io/ingress.class: `"f5`"`r`n" +
                    "  virtual-server.f5.com/http-port: ")

    if ($http) {
        $annotations += '80'
    }
    else {
        $annotations += ("443`r`n" +
            "  ingress.kubernetes.io/ssl-redirect: `"true`"`r`n" +
            "  ingress.kubernetes.io/allow-http: `"true`"")
    }

    $content = $content `
        -replace '  type: ClusterIP','  type: NodePort' `
        -replace 'replicaCount: 1','replicaCount: 2' `
        -replace 'enabled: false','enabled: true' `
        -replace 'annotations: {}', $annotations `
        -replace 'hosts:[\s\S]*?local', 'hosts: []'
}

if (!$http) {
    $content = $content -replace '  tls:[\s\S]*?\n\n', (
    "  tls:`r`n" + `
    "    - secretName: `"$certificate`"`r`n" +
    "  #    hosts: []`r`n`r`n")
}

$resources = ""
if ($maxcpu -or $maxmem) {
    $maxcpu = if ($maxcpu) {"    cpu: `"$maxcpu`"`r`n"} else {""}
    $maxmem = if ($maxmem) {"    memory: `"$maxmem`"`r`n"} else {""}

    $resources += "  limits:`r`n" + $maxcpu + $maxmem
}

if ($mincpu -or $minmem) {
    $mincpu = if ($mincpu) {"    cpu: `"$mincpu`"`r`n"} else {""}
    $minmem = if ($minmem) {"    memory: `"$minmem`"`r`n"} else {""}

    $resources += "  requests:`r`n" + $mincpu + $minmem
}
if ($resources) {
    $resources = "resources:`r`n$resources`r`n"

    $content = $content -replace 'resources: {}[\s\S]*?\n\n',$resources
}

$content | Set-Content $file  -Encoding Default
Write-Host "    : $file" -ForegroundColor DarkGreen

if ($verbose) { Write-Host $content -ForegroundColor DarkGray }

# Configuring deployment.yaml
$file = "$helm_dir\templates\deployment.yaml"
$content = $(Get-Content $file -Raw)

if ($content -match '([\s\S]*?)((.*)resources:[\s\S]*)')
{
    $yaml_deploy_pre_res = $Matches[1].TrimEnd()
    $yaml_deploy_pos_res = $Matches[2].TrimEnd()
}
else
{
    Write-Host "$file is not in the expected format. Maybe the version of Helm is not compatible whit this script." -ForegroundColor Red
    Exit
}

$content = "$yaml_deploy_pre_res
          volumeMounts:
          - name: {{ template `"$helm_project.name`" . }}-config-general-volume
            mountPath: /app/appsettings.json
            subPath: appsettings.json
          - name: {{ template `"$helm_project.name`" . }}-config-environment-volume
            mountPath: /app/appsettings.{{ .Values.data.environment }}.json
            subPath: appsettings.{{ .Values.data.environment }}.json
          - name: {{ template `"$helm_project.name`" . }}-config-nlog-volume
            mountPath: /app/nlog.config
            subPath: nlog.config
          env:
          - name: ASPNETCORE_ENVIRONMENT
            value: {{ .Values.data.environment | quote }}
          - name: $env_db_user
            valueFrom:
              secretKeyRef:
                name: {{ template `"$helm_project.fullname`" . }}-secret
                key: $secret_db_user
          - name: $env_db_pwd
            valueFrom:
              secretKeyRef:
                name: {{ template `"$helm_project.fullname`" . }}-secret
                key: $secret_db_pwd
$yaml_deploy_pos_res
      volumes:
        - name: {{ template `"$helm_project.name`" . }}-config-general-volume
          configMap:
            name: {{ template `"$helm_project.fullname`" . }}-configmap
            items:
            - key: appsettings.json
              path: appsettings.json
        - name: {{ template `"$helm_project.name`" . }}-config-environment-volume
          configMap:
            name: {{ template `"$helm_project.fullname`" . }}-configmap
            items:
            - key: appsettings.{{ .Values.data.environment }}.json
              path: appsettings.{{ .Values.data.environment }}.json
        - name: {{ template `"$helm_project.name`" . }}-config-nlog-volume
          configMap:
            name: {{ template `"$helm_project.fullname`" . }}-configmap
            items:
            - key: nlog.config
              path: nlog.config"

# Set ports
$content = $content -replace '(ports:[\s\S]*?containerPort:\s*?).*',$('$1','{{ .Values.service.port }}')

# Set probes - Readiness
$content = $content -replace '(\s*)(readinessProbe:[\s\S]*?\1)(\w)', `
                                ('$1readinessProbe:' + `
                                 '$1  httpGet:' + `
                                 '$1    path: ' + $probe_ready_url + `
                                 '$1    port: http' + `
                                 '$1  timeoutSeconds: ' + $probe_ready_timeout + `
                                 '$1  initialDelaySeconds: ' + $probe_ready_delay + `
                                 '$1  failureThreshold: ' + $probe_ready_retries + `
                                 '$1$3')
#}

# Set probes - Liveness
$content = $content -replace '(\s*)(livenessProbe:[\s\S]*?\1)(\w)', `
                            ('$1livenessProbe:' + `
                             '$1  httpGet:' + `
                             '$1    path: ' + $probe_live_url + `
                             '$1    port: http' + `
                             '$1  timeoutSeconds: ' + $probe_live_timeout + `
                             '$1  periodSeconds: ' + $probe_live_period + `
                             '$1  failureThreshold: ' + $probe_live_retries + `
                             '$1$3')

$content | Set-Content $file  -Encoding Default

Write-Host "    : $file" -ForegroundColor DarkGreen
if ($verbose) { Write-Host $content -ForegroundColor DarkGray }

# configuring ingress.yaml
$file = "$helm_dir\templates\ingress.yaml"
$content = $(Get-Content $file -Raw)

$ingressPortExpression = '{{- $ingressPort := .Values.service.port -}}'

$content = $content `
	-replace "apiVersion","$ingressPortExpression`r`napiVersion" `
	-replace 'path:[\s\S]*?backend:','backend:' `
	-replace 'servicePort: http','servicePort: {{ $ingressPort }}'

if ($content -match '([\s\S]*?)((.*)name:[\s\S]*)')
{
    $yaml_ingress_pre_name = $Matches[1].TrimEnd()
    $yaml_ingress_pos_name = $Matches[2].TrimEnd()
}
else
{
    Write-Host "$file is not in the expected format. Maybe the version of Helm is not compatible whit this script." -ForegroundColor Red
    Exit
}

$content = "$yaml_ingress_pre_name
  namespace: {{ .Values.ingress.namespace }}
$yaml_ingress_pos_name
"

$content | Set-Content $file  -Encoding Default

Write-Host "    : $file" -ForegroundColor DarkGreen
if ($verbose) { Write-Host $content -ForegroundColor DarkGray }

# Configuring configmap.yaml
$file = "$helm_dir\templates\configmap.yaml"

$content = "apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ template `"$helm_project.fullname`" . }}-configmap
  labels:
    heritage: {{ .Release.Service }}
    release: {{ .Release.Name }}
    chart: {{ .Chart.Name }}-{{ .Chart.Version }}
    app: {{ template `"$helm_project.name`" . }}
data:
{{ (.Files.Glob `"external/appsettings.json`").AsConfig | indent 2 }}
{{ (.Files.Glob .Values.data.file).AsConfig | indent 2 }}
{{ (.Files.Glob `"external/nlog.config`").AsConfig | indent 2 }}"

$content | Set-Content $file  -Encoding Default

Write-Host "    : $file" -ForegroundColor DarkGreen
if ($verbose) { Write-Host $content -ForegroundColor DarkGray }

#
# Settings files
#
Write-Output ''
Write-Host 'PREPARING APPLICATION SETTINGS  -------------------------------------------------------' -ForegroundColor Cyan

Write-Host '  - Creating application settings copies for Kubernetes:'

$files_found = @(Get-ChildItem "$($main_proj.Directory.FullName)\appsettings*.json")

$overwrite = 1

$keep_appsettings = 0
if (-not $f)
{
    if ($files_found -match "kubernetes")
    {
        Write-Host "      There are already App Settings files prepared to Kubernetes in this project. " -ForegroundColor Yellow
        if ((Read-Host -Prompt "      Do you want to overwrite them? [y/n]") -match "[yY]")
        {
            Remove-Item "$($main_proj.Directory.FullName)\appsettings*kubernetes.json"
        }
        else
        {
            $keep_appsettings = 1
        }
    }
}

$postbuild_copies = @{}

foreach($file in $files_found)
{
    if ((!(Test-Path $file.FullName)) -or $file.BaseName.Contains('.Local') -or $file.BaseName.Contains('.kubernetes'))
    {
        continue
    }

    $file_new = $file.FullName.Replace(".json", ".kubernetes.json")
    Copy-Item $file.FullName -Destination $file_new > $null

    $content = (Get-Content $file_new -Raw)

    if ($xp_blocks)
    {
        # Rename Kafka topics to avoid conflicts
        $json = ($content| ConvertFrom-Json)

        if ($json.BackgroundServices)
        {
            foreach($section in $json.BackgroundServices)
            {
                $section.psobject.Properties | ForEach-Object {
                   if (($_.Name -ne 'Reference') -and ($_.Name -ne 'RealTime'))
                   {
                        $_.Value.psobject.Properties | ForEach-Object {
                           $name = $_.Name
                           $value = [string] $_.Value
                           if ($name.Contains('TopicName') -and (-not $value.StartsWith('k8s_')))
                           {
                               # Replace the original content to minimize changes in the settings file. (ConverTo-Json reformats the file)
                               $content = ($content -ireplace "([\s,{]`"?$name`"?\s*:\s*?`")($value`")",'$1k8s_$2')
                           }
                       }
                   }
               }
            }
        }

        # Suffix cache databases with _K8S
        $content = ($content -replace '(".*?Database=)(.*?cache)','$1$2_K8S')

        # Invalidate TrainMap URLs
        $content = ($content -replace '(".*?trainmap.*?"\s?:\s?"http.*)(azure\.)(.*?")','$1xxxxx$3')
    }

    # Insert User/Password into connection strings
    # Clears CORS origins (irrelevant inside K8s cluster)
    # Suffix Kafka groups with "k8s"
    # Disable log output to anything but StructuredLog output
    $content = ($content `
        -replace '(User Id|uid)=[^";]*',"User Id=$tag_db_user" `
        -replace '(Password|pwd)=[^";]*',"Password=$tag_db_pwd" `
        -replace '(Trusted_Connection|Integrated Security)=\w+',$tag_connstr `
        -replace '(CorsOrigins.*?)\[(.*?)\]', '$1[]' `
        -replace "(Kafka[\s\S]*?GroupId.*:.*?`")(.*?(?<!$kafka_group_suffix))(`")", "`$1`$2$kafka_group_suffix`$3" `
        -replace '("?Logging"?\s*:\s*{([\s\S])*?"?Console"?\s?:\s?{[\s\S]*?"?LogLevel"?\s*:\s*{\s*"?Default"?\s*:\s*")\w*"','$1None"' `
        -replace '("?Logging"?\s*:\s*{([\s\S])*?"?Debug"?\s?:\s?{[\s\S]*?"?LogLevel"?\s*:\s*{\s*"?Default"?\s*:\s*")\w*"','$1None"' `
    )

    $content | Set-Content $file_new -Encoding Default
    Write-Host "    : $file_new" -ForegroundColor DarkGreen
    if ($verbose) { Write-Host $content -ForegroundColor DarkGray }

    $postbuild_copies[(Split-Path $file_new -Leaf)] = $file.Name

    # Creates additional values.yaml files
    if (-not $file.BaseName.Contains('kubernetes'))
    {
        if ($file.Name -match '\.(.*)\.json')
        {
            $file_env = $Matches[1]
            $file_env_lower = $file_env.ToLower()

            $yaml = "$helm_dir\values.$($file_env).yaml"

            switch ($file_env_lower) {
                "acceptance"    {
                    $ingress_host_ip = $dns_acc_ip
                    $env_code = "acc"
                    $f5_partition = $f5_acc_part
                }
                "development"    {
                    $ingress_host_ip = $dns_dev_ip
                    $env_code = "dev"
                    $f5_partition = $f5_dev_part
                }
                "production"    {
                    $ingress_host_ip = $dns_prd_ip
                    $env_code = ""
                    $f5_partition = $f5_prd_part
                }
                "test"    {
                    $ingress_host_ip = $dns_tst_ip
                    $env_code = "tst"
                    $f5_partition = $f5_tst_part
                }
                Default         {
                    $ingress_host_ip = $unknown
                    $env_code = $unknown
                }
            }

            if ($xp_blocks) {
                $ingress_host_name = $helm_project + "-k8s." + $env_code + "mydomain.com"   # CHANGE HERE!
            }
            else {
                $ingress_host_name = ($ext_url_template -replace '{ENV}',$env_code) -replace '\.-','.'
            }

            $content = ("data:`r`n" +
                        "  db:`r`n" +
                        "    user: `"$unknown`"`r`n" +
                        "    password: `"$unknown`"`r`n" +
                        "  file: `"external/$($file.Name)`"`r`n" +
                        "  environment: `"$file_env`"`r`n" +
                        "ingress:`r`n" +
                        "  namespace: rivdec-$file_env_lower`r`n" +
                        "  annotations: `r`n" +
                        "    virtual-server.f5.com/ip: `"$ingress_host_ip`"`r`n" +
                        "    virtual-server.f5.com/partition: `"$f5_partition`"`r`n" +
                        "  hosts: `r`n" +
                        "    - $ingress_host_name`r`n")

            $content | Out-File $yaml  -Encoding Default

            Write-Host "    : $yaml" -ForegroundColor DarkGreen
            if ($verbose) { Write-Host $content -ForegroundColor DarkGray }
        }
    }
}

#
# SECRETS
#
Write-Output ''
Write-Host 'KUBERNETES SECRETS  -------------------------------------------------------------------' -ForegroundColor Cyan

Write-Host '  - Creating secret file... ' -NoNewline
$yaml = "$helm_dir\templates\secrets.yaml"

$content = "apiVersion: v1
kind: Secret
metadata:
  name: {{ template `"$helm_project.fullname`" . }}-secret
  labels:
    app: {{ template `"$helm_project.fullname`" . }}
    chart: `"{{ .Chart.Name }}-{{ .Chart.Version }}`"
    release: `"{{ .Release.Name }}`"
    heritage: `"{{ .Release.Service }}`"
type: Opaque
data:
  `"$secret_db_user`": |-
    {{ .Values.data.db.user | b64enc }}
  `"$secret_db_pwd`": |-
    {{ .Values.data.db.password | b64enc }}"

$content | Out-File $yaml  -Encoding Default

Write-Host $yaml -ForegroundColor DarkGreen
if ($verbose) { Write-Host $content -ForegroundColor DarkGray }

#
# JENKINS
#
Write-Output ''
Write-Host 'JENKINS CONFIG  -----------------------------------------------------------------------' -ForegroundColor Cyan

$file = $solution_dir + '\Jenkinsfile'
Write-Host '  - Modifying Jenkins file... ' -NoNewline

$content = (Get-Content $file -Raw)

if ($content.Contains("import $jenkins_namespace.DockerPublishOptions"))  # CHANGE HERE!
{
    Write-Host 'already updated!' -ForegroundColor DarkGray
}
else
{
    $content = ($content `
        -replace '(package.*\s+)(import)', "`$1import $jenkins_namespace.DockerPublishOptions`r`n`$2") ` # CHANGE HERE!
        -replace '(new MicroservicesJob[\s\S]*)', "def dockerPublishOptions = new DockerPublishOptions()
dockerPublishOptions.dockerRepository = '$docker_repo'
dockerPublishOptions.dockerImageName = '$docker_img'
dockerPublishOptions.dockerFileLocation = '$($main_proj.Directory.Name)'

options.dockerPublishOptions = dockerPublishOptions
options.helmChartName = '$helm_project'

`$1"

    $content | Out-File $file  -Encoding Default

    Write-Host $file -ForegroundColor DarkGreen
    if ($verbose) { Write-Host $content -ForegroundColor DarkGray }
}

#
# NLog
#
Write-Output ''
Write-Host 'PREPARING LOG CONFIG FOR CONTAINER ----------------------------------------------------' -ForegroundColor Cyan
Set-Location $main_proj.Directory.FullName > $null

Write-Host "  - Renaming Nlog.config to lower case (avoid problems on Linux containers)... " -NoNewline
Rename-Item 'NLog.config' 'nlog.config' > $null
Write-Host "OK" -ForegroundColor DarkGreen

Write-Host '  - Creating NLog config for Docker... ' -NoNewline
$file_new = ($main_proj.Directory.FullName + "\nlog.docker.config")
$content = '<nlog xmlns="http://www.nlog-project.org/schemas/NLog.xsd"
      xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
      autoReload="true"
      throwExceptions="false"
      internalLogLevel="info"
      internalLogFile="internal-nlog.txt">
  <targets>

    <target xsi:type="ColoredConsole" name="structuredLog">
      <layout xsi:type="JsonLayout" includeAllProperties="true">
        <attribute name="time" layout="${longdate:universalTime:true}" />
        <attribute name="level" layout="${level:upperCase=true}" />
        <attribute name="logger" layout="${logger}" />
        <attribute name="kafkaTag" layout="${mdlc:item=KafkaTag}"/>
        <attribute name="keyTag" layout="${mdlc:item=KeyTag}"/>
        <attribute name="message" layout="${message}" />
        <attribute name="exception" layout="${exception:format=tostring}" />
        <attribute name="aspRequestMethod" layout="${aspnet-request-method}" />
        <attribute name="aspRequestUrl" layout="${aspnet-request-url:IncludePort=true:IncludeQueryString=true}" />
        <attribute name="aspMcvAction" layout="${aspnet-mvc-action}" />
        <attribute name="machineName" layout="${machinename}" />
        <attribute name="threadid" layout="${threadid}" />
        <attribute name="assemblyVersion" layout="${assembly-version}" />
        <attribute name="environment" layout="${environment:ASPNETCORE_ENVIRONMENT}" />
      </layout>
    </target>

  </targets>

  <rules>
    <!--Skip Microsoft logs and so log only own logs-->
    <logger name="Microsoft.*" minlevel="Warn" writeTo="structuredLog" />
    <logger name="Microsoft.EntityFrameworkCore.Database.*" minlevel="Info" writeTo="structuredLog" />
    <logger name="' + $base_namespace + '.*" minlevel="Trace" writeTo="structuredLog" final="true" />
  </rules>
</nlog>'

$content | Out-File $file_new  -Encoding Default

Write-Host $file_new -ForegroundColor DarkGreen
if ($verbose) { Write-Host $content -ForegroundColor DarkGray }

$postbuild_copies["nlog.docker.config"] = "nlog.config"

#
# DOCKER
#
Write-Output ''
Write-Host 'DOCKER FILES  -------------------------------------------------------------------------' -ForegroundColor Cyan

# Docker file
$file = $main_proj.Directory.FullName + '\dockerfile'
Write-Host '  - Writing Docker file... ' -NoNewline

$content = "FROM microsoft/$dotnet_image
WORKDIR /app
EXPOSE $port
COPY ./bin/Release/publish .
ENTRYPOINT [`"dotnet`", `"$($main_proj.BaseName).dll`"]"

$content | Out-File $file -Encoding Default

Write-Host $file -ForegroundColor DarkGreen
if ($verbose) { Write-Host $content -ForegroundColor DarkGray }

# Ignore file
$file = $main_proj.Directory.FullName + '\.dockerignore'
Write-Host '  - Writing Ignore file... ' -NoNewline

$content = "**/appsettings.json
**/appsettings.*.json
**/hosting.*.json
**/nlog*.config"

$content | Out-File $file -Encoding Default

Write-Host $file -ForegroundColor DarkGreen
if ($verbose) { Write-Host $content -ForegroundColor DarkGray }


#
# GIT
#
Write-Output ''
Write-Host 'GIT FILES  ----------------------------------------------------------------------------' -ForegroundColor Cyan

# Git ignore file
$file = $solution_dir + '\.gitignore'
Write-Host '  - Writing Git Ignore file... ' -NoNewline

$content = (Get-Content $file -Raw)
if (-not ($content -match 'helm/\*\*'))
{
    Add-Content $file "
helm/**/*.tgz
helm/**/external/*" -Encoding Default
}
Write-Host 'OK' -ForegroundColor DarkGreen


#
# Solution and project
#

Write-Output ''
Write-Host 'UPDATING SOLUTION  --------------------------------------------------------------------' -ForegroundColor Cyan

# Insert Helm folder into Solution as a WebSite
# We dont need to check if folder already included. VS handles that automatically
$file = $solution.FullName
Write-Host '  - Including Helm folder into solution... ' -NoNewline

$content = $(Get-Content $file -Raw)

if ($content.Contains('helm\'))
{
    Write-Host 'already updated!' -ForegroundColor DarkGray
}
else
{
    if ($content -match '([\s\S]*?)(Project\("[\s\S]*)')
    {
        $content = $Matches[1] +
        'Project("{E24C65DC-7377-472B-9ABA-BC803B73C61A}") = "helm", "helm\", "{2BE35EF5-677B-46E4-BB59-59762DAEF6E8}' +
        "`r`nEndProject`r`n" +
        $Matches[2]
    }

    if ($content -match '([\s\S]*?GlobalSection\(ProjectConfigurationPlatforms\)\s=\spostSolution.*)([\s\S]*)')
    {
        $content = $Matches[1] +
        "`t`t{2BE35EF5-677B-46E4-BB59-59762DAEF6E8}.Debug|Any CPU.ActiveCfg = Debug|Any CPU`r`n" +
        "`t`t{2BE35EF5-677B-46E4-BB59-59762DAEF6E8}.Release|Any CPU.ActiveCfg = Debug|Any CPU" +
        $Matches[2]
    }

    $content | Set-Content ($solution.FullName) -Encoding UTF8

    Write-Host $($solution.FullName) -ForegroundColor DarkGreen
    if ($verbose) { Write-Host $content -ForegroundColor DarkGray }
}

$file = $main_proj.FullName
Write-Host '  - Post Build Events: Copy files to Helm folder'

# It's safer to work on csproj as XML so we preserve any previous Post Build events
# without the risk of duplicating the tags
$content = New-Object XML
$content.Load($file) > $null

$target_node = $content.SelectSingleNode('Project/Target[@Name="PostBuild" and @AfterTargets="PostBuildEvent"]')

if (-not $target_node)
{
    $target_node = $content.CreateElement('Target')

    $attr = $content.CreateAttribute('Name')
    $attr.Value = "PostBuild"
    $target_node.Attributes.Append($attr) > $null

    $attr = $content.CreateAttribute('AfterTargets')
    $attr.Value = "PostBuildEvent"
    $target_node.Attributes.Append($attr) > $null

    $attr = $content.CreateAttribute('Condition')
    $attr.Value = "`$(SolutionDir) != '*Undefined*'"
    $target_node.Attributes.Append($attr) > $null

    $content.Project.AppendChild($target_node) > $null
}

ForEach($source in $postbuild_copies.Keys)
{
    $target = $postbuild_copies[$source]

    $file_new = '$(ProjectDir)' + $source

    # Removes the old operation if it alredy exists
    $node = $target_node.SelectSingleNode('Copy[@SourceFiles="' + $file_new + '"]')
    if ($node)
    {
        $node.ParentNode.RemoveChild($node)
    }

    $node = $content.CreateElement('Copy')
    $attr = $content.CreateAttribute('SourceFiles')
    $attr.Value = $file_new
    $node.Attributes.Append($attr) > $null
    if ($target -eq '')
    {
        $attr = $content.CreateAttribute('DestinationFolder')
    }
    else
    {
        $attr = $content.CreateAttribute('DestinationFiles')
    }
    $attr.Value = '$(SolutionDir)' + "helm\$helm_project\external\$target"
    $node.Attributes.Append($attr) > $null
    $target_node.AppendChild($node) > $null
    Write-Host "    : COPY $source => ..\helm\$helm_project\external\$target" -ForegroundColor DarkGreen
}

$content.Save($file)
if ($verbose)
{
    $content = (Get-Content $file -Raw)
    Write-Host $content -ForegroundColor DarkGray
}






# Manual steps
Write-Host ''
Write-Host ''
Write-Host ''
Write-Host 'TODO: MANUAL SETTINGS -----------------------------------------------------------------' -ForegroundColor Yellow
Write-Host "    . Change descriptions in $helm_dir\Chart.yaml (optional)" -ForegroundColor Yellow
Write-Host "    . Docker image will be created using .NET Core Runtime only. If you need an image with the sdk, then use microsoft/aspnetcore-build or dotnet:2.1-sdk. More info here https://github.com/aspnet/aspnet-docker/tree/master/2.1" -ForegroundColor Yellow
Write-Host "    . Check if the option 'Build' is disabled for the Helm project in Visual Studio (menu Build -> Configuration Manager -> Release)" -ForegroundColor Yellow
Write-Host "    . Check in the appsettings.*.kubernetes.json if the Kafka group ID is the correct one for this application (a '$kafka_group_suffix' suffix has been applied)." -ForegroundColor Yellow
Write-Host "    . Check if 'service.port' value in $helm_dir\values.yaml needs to be changed (it was attributed the default port $default_port)" -ForegroundColor Yellow
if ($keep_appsettings)
{
    Write-Host '    . Verify the content of all "appsettings.*.kubernetes.json" files to check if all configurations are correct and updated.' -ForegroundColor Yellow
	Write-Host '    . Check for any absolute paths in the "appsettings.*.kubernetes.json" files and replace them by relative paths.' -ForegroundColor Yellow
}
if (!$minikube) {
	Write-Host '    . Verify the content of all "values.*.yaml" files to check if the ingress information is correct.' -ForegroundColor Yellow
}

Write-Host ''
Write-Host ''
Write-Host 'OPERATION COMPLETED!' -ForegroundColor Green
Write-Host 'Please, check all TODO items to fully configure this solution for Kubernetes.'
Write-Host 'Have a nice day.'
Write-Host ''
Set-Location $solution_dir

<#

#>