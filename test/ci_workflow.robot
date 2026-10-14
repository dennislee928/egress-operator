*** Settings ***
Documentation       The CI workflow must keep the gates that stop each fixed issue from coming back.
...                 (Checks the workflow definition; the jobs themselves run in GitHub Actions.)
Resource            resources/common.resource
Test Tags           ci


*** Variables ***
${WORKFLOW}         .github/workflows/ci.yml


*** Test Cases ***
CI Runs On Pushes, Pull Requests And Weekly
    Repo File Should Contain    ${WORKFLOW}    pull_request:
    Repo File Should Contain    ${WORKFLOW}    branches: [master]
    Repo File Should Contain    ${WORKFLOW}    schedule:

Make Test Runs Without Pre-installed Envtest Assets (#50)
    Repo File Should Contain    ${WORKFLOW}    run: make test
    Repo File Should Contain    ${WORKFLOW}    run: make coverage-check
    Repo File Should Not Contain    ${WORKFLOW}    setup-envtest@latest

Generated Code And CRDs Are Verified (#49, #17)
    Repo File Should Contain    ${WORKFLOW}    run: make verify-generated
    Repo File Should Contain    ${WORKFLOW}    TestNoAnonymousStructFields

Envoy Config Is Validated By Envoy (#28)
    Repo File Should Contain    ${WORKFLOW}    run: make validate-envoy-config

Images, Vulnerabilities And Acceptance Suites Are Checked
    Repo File Should Contain    ${WORKFLOW}    docker buildx build
    Repo File Should Contain    ${WORKFLOW}    govulncheck
    Repo File Should Contain    ${WORKFLOW}    make robot

Egress Is Validated On A Real Cluster (#10, #21)
    Repo File Should Contain    ${WORKFLOW}    --include issue-10

Workflow Passes actionlint
    [Tags]    slow
    Command Should Succeed    go    run    github.com/rhysd/actionlint/cmd/actionlint@v1.7.12    timeout=10 min
