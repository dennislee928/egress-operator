*** Settings ***
Documentation       Issue #21: client pods were labelled `egress.monzo.com/allowed-gateway: <name>` as the README said,
...                 but the gateway NetworkPolicy selects `egress.monzo.com/allowed-<name>: "true"`.
...                 The README is fixed and a unit test pins the label contract.
...                 https://github.com/monzo/egress-operator/issues/21
Resource            resources/common.resource
Test Tags           issue-21


*** Test Cases ***
NetworkPolicy Selects Pods With The Allowed Label
    ${result}=    Command Should Succeed    go    test    -count\=1    -v
    ...    -run    TestNetworkPolicyAllowsPodsWithAllowedLabel    ./controllers/    timeout=5 min
    Should Contain    ${result.stdout}    --- PASS: TestNetworkPolicyAllowsPodsWithAllowedLabel

README Documents The Label The Controller Actually Uses
    Repo File Should Contain    README.md    egress.monzo.com/allowed-<name>: "true"
    Repo File Should Contain    README.md    egress.monzo.com/allowed-google: "true"
    Repo File Should Not Contain    README.md    allowed-gateway: nameofgateway

README Explains Why Traffic Is Not Blocked Without Default Deny
    Repo File Should Contain    README.md    The operator only *permits* traffic through gateways
