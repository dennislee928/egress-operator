*** Settings ***
Documentation       Snyk findings (`snyk test`, `snyk code test`) and container scanning.
...                 See docs/security/snyk-triage.md. Snyk checks are skipped when the Snyk CLI is not
...                 authenticated; govulncheck needs no account.
Resource            resources/common.resource
Test Tags           snyk    security


*** Variables ***
${GOVULNCHECK}      golang.org/x/vuln/cmd/govulncheck@v1.8.0


*** Test Cases ***
Go Code Is Not Affected By Known Vulnerabilities
    [Documentation]    Runs with the toolchain pinned in go.mod (what the images are built with): govulncheck
    ...    checks the standard library of the Go version that runs it, not the one in go.mod.
    [Tags]    slow
    ${content}=    Get File    ${ROOT}${/}go.mod
    ${toolchain}=    Get Regexp Matches    ${content}    (?m)^toolchain (go\\S+)$    1
    ${root_module}=    Command Should Succeed    go    run    ${GOVULNCHECK}    ./...
    ...    env:GOTOOLCHAIN=${toolchain}[0]    timeout=15 min
    Should Contain    ${root_module.stdout}    No vulnerabilities found
    ${plugin}=    Command Should Succeed    go    run    ${GOVULNCHECK}    ./...
    ...    cwd=${ROOT}${/}coredns-plugin    env:GOTOOLCHAIN=${toolchain}[0]    timeout=15 min
    Should Match Regexp    ${plugin.stdout}    No vulnerabilities found|Your code is affected by 0 vulnerabilities

Vendored Modules Match go.mod
    Command Should Succeed    go    mod    verify
    Command Should Succeed    go    mod    vendor
    Command Should Succeed    git    diff    --exit-code    --stat    --    vendor

Third-party Code Is Excluded From Snyk Code
    Repo File Should Contain    .snyk    - vendor/**
    Repo File Should Contain    docs/security/snyk-triage.md    InsecureSkipVerify

Snyk Open Source Scan Is Clean
    [Tags]    slow    snyk-auth
    Require Snyk
    Command Should Succeed    npx    --yes    snyk    test    --all-projects    timeout=15 min

Snyk Code Scan Is Clean
    [Tags]    slow    snyk-auth
    Require Snyk
    ${result}=    Command Should Succeed    npx    --yes    snyk    code    test    timeout=15 min
    Should Match Regexp    ${result.stdout}    Total issues:\\s+0

Container Scan Script Finds Every Dockerfile
    ${result}=    Command Should Succeed    hack/snyk-container-scan.sh    --list
    Should Contain    ${result.stdout}    dockerfile  Dockerfile
    Should Contain    ${result.stdout}    dockerfile  coredns-plugin/Dockerfile
    Should Not Contain    ${result.stdout}    vendor/

Container Scan Script Discovers Compose Files And Containerfiles
    ${dir}=    Set Variable    ${OUTPUT DIR}${/}container-discovery
    Remove Directory    ${dir}    recursive=True
    Create File    ${dir}${/}svc${/}Containerfile    FROM alpine:3.20\n
    Create File    ${dir}${/}app.Dockerfile    FROM alpine:3.20\n
    Create File    ${dir}${/}docker-compose.yml    services: {}\n
    Create File    ${dir}${/}compose.override.yaml    services: {}\n
    Create File    ${dir}${/}vendor${/}x${/}Dockerfile    FROM alpine:3.20\n
    ${result}=    Command Should Succeed    hack/snyk-container-scan.sh    --list    ${dir}
    Should Contain    ${result.stdout}    dockerfile  svc/Containerfile
    Should Contain    ${result.stdout}    dockerfile  app.Dockerfile
    Should Contain    ${result.stdout}    compose     docker-compose.yml
    Should Contain    ${result.stdout}    compose     compose.override.yaml
    Should Not Contain    ${result.stdout}    vendor

Final Stage Base Images Pass Snyk Container Test
    [Tags]    slow    snyk-auth
    Require Snyk
    ${result}=    Run In Repo    hack/snyk-container-scan.sh    --base-only    timeout=20 min
    Should Contain    ${result.stdout}    snyk container test gcr.io/distroless/static:nonroot
    Should Contain    ${result.stdout}    final stage is FROM scratch
    Should Be Equal As Integers    ${result.rc}    0    msg=${result.stdout}


*** Keywords ***
Require Snyk
    ${whoami}=    Run Process    npx    --yes    snyk    whoami    --experimental    stderr=STDOUT
    Skip If    ${whoami.rc} != 0    Snyk CLI is not authenticated (run `snyk auth` or set SNYK_TOKEN)
