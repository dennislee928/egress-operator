*** Settings ***
Documentation       Issue #45: how to let unrestricted workloads bypass the gateway DNS rewrite.
...                 Answered in the README FAQ with the CoreDNS `view` plugin, which must be compiled into the
...                 egress-operator CoreDNS build for that advice to work.
...                 https://github.com/monzo/egress-operator/issues/45
Resource            resources/common.resource
Test Tags           issue-45


*** Test Cases ***
FAQ Documents Scoping DNS Rewrites To Some Workloads
    Repo File Should Contain    README.md    Can unrestricted workloads bypass the gateways
    Repo File Should Contain    README.md    view restricted
    Repo File Should Contain    README.md    egressoperator egress-operator-system cluster.local

Egress Operator CoreDNS Build Includes The View Plugin
    [Tags]    slow
    ${bin}=    Set Variable    ${OUTPUT DIR}${/}coredns-issue45
    Run Process    go    build    -o    ${bin}    ./cmd    cwd=${ROOT}${/}coredns-plugin    timeout=15 min
    ...    stderr=STDOUT    stdout=${OUTPUT DIR}${/}coredns-build.log
    File Should Exist    ${bin}
    ${result}=    Run Process    ${bin}    -plugins    stderr=STDOUT
    Should Match Regexp    ${result.stdout}    (?m)^\s*(dns\.)?view$
    Should Match Regexp    ${result.stdout}    (?m)^\s*(dns\.)?egressoperator$
