# .NET Core Deployment to Kubernetes

Powershell script to automate configuration of a .NET Core project to be deployed in a Kubernetes cluster using Helm.

## Getting Started

- Just download the latest version.
- Check all consts defined in the script and change the ones necessary to your environment(s) (URLs, IP addresses, default values...)
- Run it!

**Note:** You can run this script in an interactive way, providing all parameters manually, or provide the parameters in the command line and execute with no intervention (i.e. directly from a CI/CD pipeline)

### Prerequisites

- **PowerShell 5.0+:** Although PowerShell is present in most of Windows machines, this script uses some PowerShell 5.0 features, so be sure it is up to date.
- **Helm 1.6** Should work with newer versions of Helm too but not tested yet.

### Executing (Interactive Mode)

- Open a Powershell window
- Navigate to the solution folder. Ex: `cd <solution folder>`
- Type the relative or absolute path of the script. Ex: `..\prepare-to-k8s.ps1`
- Follow the instructions

### Executing (Command Line)

- Open a PowerShell window
- Navigate to the script folder or type the full path. Ex: `C:\Tools\k8s\scripts\prepare-to-k8s.ps1 {parameters}`

#### Parameters

| Param                 | Description
| ------                | ------------
| -s *path*             | Solution file name. If omited the script needs to run in the solution folder.
| -p *path*             | Project file path. If omited the script prompts the user for it.
| -h *name*             | Helm project name. If omited the script prompts the user for it.
| -port *port*          | Port number of the external endpoint of the serivce. If omitted, uses value in hosting.json
| -readiness *settings* | Set readiness probe configuration in the format *url[,delay[,timeout[,retries]]]*.
| -liveness *settings*  | Set liveness probe configuration in the format *url[,interval[,timeout[,retries]]]*.
| -maxcpu  *value*      | Limits CPU cores usage for the pod. Ex: 1.5 or 1500m limits usage to 1.5 cores.
| -maxmem  *value*      | Limits memory usage for the pod, in bytes. Ex: 2147483648 = 2000Mi = 2Gi
| -mincpu  *value*      | Require this free CPU to schedule pod in a node. This can avoid pod from being started.
| -minmem  *value*      | Require this free memory to schedule pod in a node. This can avoid pod from being started.
| -url, -u *url*        | External URL. Inform service alias only of full URL with {ENV} as placeholder for environment code. Ex: *svc-{ALIAS}.api.{ENV}-mydomain.com*
| -http                 | Indicates that service is to be configured for HTTP access (configures HTTPS if omitted).
| -certificate *name*   | Certificate name (as installed in F5 partition).
| -f                    | Force the overwriting all files without confirmation.
| -help                 | Shows command line parameters documentation.
| -verbose, -v          | Show the content of all modified/created files.
| -stable               | Disable experimental/unstable changes.
| -minikube             | Prepare the application to deploy in a local Kubernetes cluster (Minikube).

## Deployment

Refer to [Helm](https://helm.sh/) page for details on how to register a Helm Chart and then deploy your application to Kubernetes.

## Built With

* [PowerShell](https://github.com/PowerShell/PowerShell)
* [Helm 1.6](https://helm.sh/)

## Authors

* [**Ricardo A.**](https://www.linkedin.com/in/ricardo-alkain/) - *Senior Software Engineer*

## License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details

## Acknowledgments

This script idea has born during a work for Belgian Rails company. We were faced with the need to create and modify Helm charts for dozens of microservices being migrated to our Kubernetes cluster.
Just another good example of laziness inspiring people XD

### TODO

- Make the script more "generic". Still contains lots of conventions that can/should be configurable by parameters.
- Option to fully disable interactive mode when running from command line (automatically choose default values)
- Make a Bash version of the script to use it in other OS.
- Option to rollback changes made by the script.
