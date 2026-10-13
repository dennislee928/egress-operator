*** Settings ***
Documentation       Issue #23: regex dnsName values are not supported. They are now rejected by CRD validation
...                 instead of being silently accepted, and the FAQ explains why.
...                 https://github.com/monzo/egress-operator/issues/23
Resource            resources/common.resource
Test Tags           issue-23


*** Test Cases ***
CRD Declares A Hostname Pattern For dnsName
    Repo File Should Contain    config/crd/bases/egress.monzo.com_externalservices.yaml    maxLength: 253
    Repo File Should Contain    config/crd/bases/egress.monzo.com_externalservices.yaml    pattern: ^([a-zA-Z0-9_]

API Server Rejects Regex And Wildcard dnsName And Accepts Hostnames
    [Tags]    slow
    ${result}=    Run Controller Specs    dnsName validation
    Should Contain    ${result.stdout}    rejects ^global\\.azure-devices-provisioning\\.net$
    Should Contain    ${result.stdout}    rejects *.example.com
    Should Contain    ${result.stdout}    accepts global.azure-devices-provisioning.net
    Should Match Regexp    ${result.stdout}    Ran 7 of \\d+ Specs

FAQ Answers The Regex Question
    Repo File Should Contain    README.md    Can `dnsName` be a regular expression or a wildcard?
