*** Settings ***
Documentation       Issue #10: there was no usage / quickstart guide. docs/quickstart.md walks through the
...                 Kubernetes Egress Policy Validation Lab (hack/kind/e2e.sh), and this suite runs that lab:
...                 a Kind + Calico cluster where allowed and denied egress is checked for real.
...                 https://github.com/monzo/egress-operator/issues/10
...
...                 The lab needs Docker, kind, kubectl and internet access. It is tagged `e2e` and skipped
...                 when those are missing. Set KEEP_CLUSTER=1 to keep the cluster after the suite.
Resource            resources/common.resource
Suite Setup         Bring Up Lab
Suite Teardown      Tear Down Lab
Test Tags           issue-10


*** Test Cases ***
Quickstart Is Linked From The README
    Repo File Should Contain    README.md    (docs/quickstart.md)
    File Should Exist    ${ROOT}${/}docs${/}quickstart.md

Sample ExternalService Is A Real Example
    Repo File Should Not Contain    config/samples/egress_v1_externalservice.yaml    foo: bar
    Repo File Should Contain    config/samples/egress_v1_externalservice.yaml    dnsName: example.com

DNS For The Destination Resolves To The Gateway
    [Tags]    e2e
    Lab Check    dns-hijacked

Labelled Pod Reaches The Destination Through The Gateway
    [Tags]    e2e
    Lab Check    allowed-via-gateway

Pod With The Old README Label Is Denied
    [Tags]    e2e    issue-21
    Lab Check    wrong-label-denied

Unlabelled Pod Is Denied
    [Tags]    e2e
    Lab Check    unlabelled-denied

Direct Egress Bypassing The Gateway Is Denied
    [Tags]    e2e
    Lab Check    direct-egress-denied

Unrestricted Control Pod Can Reach The Destination Directly
    [Documentation]    Proves the denials above come from the policies, not from missing internet access.
    [Tags]    e2e
    Lab Check    control-direct-allowed


*** Keywords ***
Bring Up Lab
    ${missing}=    Run Process    sh    -c    command -v docker && command -v kind && command -v kubectl && docker info
    Set Suite Variable    ${LAB_AVAILABLE}    ${missing.rc == 0}
    IF    not ${LAB_AVAILABLE}    RETURN
    Command Should Succeed    hack/kind/e2e.sh    up    timeout=40 min

Tear Down Lab
    ${keep}=    Get Environment Variable    KEEP_CLUSTER    ${EMPTY}
    IF    ${LAB_AVAILABLE} and not $keep    Run In Repo    hack/kind/e2e.sh    down

Lab Check
    [Arguments]    ${name}
    Skip If    not ${LAB_AVAILABLE}    docker, kind or kubectl not available
    Command Should Succeed    hack/kind/e2e.sh    check    ${name}    timeout=3 min
