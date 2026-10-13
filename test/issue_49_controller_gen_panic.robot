*** Settings ***
Documentation       Issue #49: `make manifests` panicked in controller-gen (crd.structToSchema).
...                 Root cause: an anonymous struct field type (TopologySpreadSkews, added in #47) in the CRD
...                 spec. controller-gen v0.16.5-v0.21.0 panic on it; v0.22.0 reports
...                 "inline struct types are not supported". Fixed upstream in 8d3c2be by using a named type.
...                 https://github.com/monzo/egress-operator/issues/49
Resource            resources/common.resource
Suite Setup         Command Should Succeed    make    controller-gen    timeout=10 min
Test Tags           issue-49

*** Variables ***
${REPRO_PKG}        api${/}issue49repro
${TEMPLATE}         test${/}fixtures${/}issue49${/}types.go.tmpl
${ANONYMOUS}        struct{ Zone int `json:"zone,omitempty"` }


*** Test Cases ***
Minimal Repro: Anonymous Struct Field Breaks CRD Generation
    [Teardown]    Remove Repro Package
    Write Repro Package    ${ANONYMOUS}
    ${result}=    Generate CRD For Repro
    Should Not Be Equal As Integers    ${result.rc}    0
    Should Match Regexp    ${result.stdout}    nil pointer dereference|inline struct types are not supported

Minimal Repro: Named Struct Type Generates Fine
    [Teardown]    Remove Repro Package
    Write Repro Package    Skews
    ${result}=    Generate CRD For Repro
    Should Be Equal As Integers    ${result.rc}    0    msg=${result.stdout}

Make Manifests Succeeds And Generated Files Are Up To Date
    Command Should Succeed    make    verify-generated    timeout=10 min

API Types Have No Anonymous Struct Fields
    Command Should Succeed    go    test    -count\=1    -run    TestNoAnonymousStructFields    ./api/...


*** Keywords ***
Write Repro Package
    [Arguments]    ${field_type}
    ${template}=    Get File    ${ROOT}${/}${TEMPLATE}
    ${source}=    Replace String    ${template}    FIELD_TYPE    ${field_type}
    Create File    ${ROOT}${/}${REPRO_PKG}${/}types.go    ${source}

Generate CRD For Repro
    ${out}=    Set Variable    ${OUTPUT DIR}${/}issue49-crd
    ${result}=    Run In Repo    bin/controller-gen    crd    paths\=./api/issue49repro/...
    ...    output:crd:artifacts:config\=${out}    env:CGO_ENABLED=0    timeout=5 min
    RETURN    ${result}

Remove Repro Package
    Remove Directory    ${ROOT}${/}${REPRO_PKG}    recursive=True
