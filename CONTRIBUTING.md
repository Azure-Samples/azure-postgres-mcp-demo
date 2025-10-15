# Contributing to Azure MCP PostgreSQL Server

This project welcomes contributions and suggestions. Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit [Contributor License Agreements](https://cla.opensource.microsoft.com).

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

 - [Code of Conduct](#coc)
 - [Issues and Bugs](#issue)
 - [Feature Requests](#feature)
 - [Development Setup](#setup)
 - [Submission Guidelines](#submit)

## <a name="coc"></a> Code of Conduct
Help us keep this project open and inclusive. Please read and follow our [Code of Conduct](https://opensource.microsoft.com/codeofconduct/).

## <a name="issue"></a> Found an Issue?
If you find a bug in the source code or a mistake in the documentation, you can help us by
[submitting an issue](#submit-issue) to the GitHub Repository. Even better, you can
[submit a Pull Request](#submit-pr) with a fix.

## <a name="feature"></a> Want a Feature?
You can *request* a new feature by [submitting an issue](#submit-issue) to the GitHub
Repository. If you would like to *implement* a new feature, please submit an issue with
a proposal for your work first, to be sure that we can use it.

* **Small Features** can be crafted and directly [submitted as a Pull Request](#submit-pr).

## <a name="setup"></a> Development Setup

### Prerequisites
- .NET 8.0 SDK
- Docker Desktop
- Azure CLI
- PostgreSQL Client
- Azure subscription with access to:
  - Azure Container Apps
  - Azure Database for PostgreSQL Flexible Server
  - Azure Container Registry (optional)

### Local Development
1. Clone the repository:
   ```bash
   git clone https://github.com/Azure-Samples/azure-postgres-mcp-demo.git
   cd azure-postgres-mcp-demo
   ```

2. Build the project:
   ```bash
   dotnet build src/AzMcpPostgresServer.csproj
   ```

3. Run the project locally:
   ```bash
   dotnet run --project src/AzMcpPostgresServer.csproj
   ```

### Testing
- Use the provided `mcp-client.html` for testing MCP functionality
- Follow the deployment scripts in `/scripts` for end-to-end testing
- Ensure all PostgreSQL connections work with Entra ID authentication

### Docker Development
Build and test the Docker image:
```bash
docker build -f docker/Dockerfile -t azure-mcp-postgres-server .
docker run -p 8080:8080 azure-mcp-postgres-server
```

## <a name="submit"></a> Submission Guidelines

### <a name="submit-issue"></a> Submitting an Issue
Before you submit an issue, search the archive, maybe your question was already answered.

If your issue appears to be a bug, and hasn't been reported, open a new issue.
Help us to maximize the effort we can spend fixing issues and adding new
features, by not reporting duplicate issues.  Providing the following information will increase the
chances of your issue being dealt with quickly:

* **Overview of the Issue** - if an error is being thrown a non-minified stack trace helps
* **Version** - what version is affected (e.g. 0.1.2)
* **Motivation for or Use Case** - explain what are you trying to do and why the current behavior is a bug for you
* **Browsers and Operating System** - is this a problem with all browsers?
* **Reproduce the Error** - provide a live example or a unambiguous set of steps
* **Related Issues** - has a similar issue been reported before?
* **Suggest a Fix** - if you can't fix the bug yourself, perhaps you can point to what might be
  causing the problem (line of code or commit)

You can file new issues by providing the above information at:
https://github.com/Azure-Samples/azure-postgres-mcp-demo/issues/new

### <a name="submit-pr"></a> Submitting a Pull Request (PR)
Before you submit your Pull Request (PR) consider the following guidelines:

* Search the repository's [pull requests](https://github.com/Azure-Samples/azure-postgres-mcp-demo/pulls) for an open or closed PR
  that relates to your submission. You don't want to duplicate effort.

* Make your changes in a new git fork:

* Commit your changes using a descriptive commit message
* Push your fork to GitHub:
* In GitHub, create a pull request
* If we suggest changes then:
  * Make the required updates.
  * Rebase your fork and force push to your GitHub repository (this will update your Pull Request):

    ```shell
    git rebase main -i
    git push -f
    ```

That's it! Thank you for your contribution!
