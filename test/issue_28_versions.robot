*** Settings ***
Documentation       Issue #28: CoreDNS, Envoy and other components were out of date, and documented versions
...                 had drifted from the code. Versions are now bumped, kept consistent, validated against the real
...                 Envoy binary, and kept fresh by Dependabot.
...                 https://github.com/monzo/egress-operator/issues/28
Resource            resources/common.resource
Test Tags           issue-28


*** Test Cases ***
Go Toolchain Is Patched And Consistent Across Modules And Dockerfile
    ${root_toolchain}=    Get Toolchain    go.mod
    ${plugin}=    Get Toolchain    coredns-plugin/go.mod
    Should Be Equal    ${root_toolchain}    ${plugin}
    Version Should Be At Least    ${root_toolchain}    1.26.6
    Repo File Should Contain    Dockerfile    FROM golang:${root_toolchain}@sha256:

CoreDNS Is At Least 1.14.7
    ${result}=    Command Should Succeed    go    list    -m    -f    {{.Version}}    github.com/coredns/coredns
    ...    cwd=${ROOT}${/}coredns-plugin
    Version Should Be At Least    ${result.stdout.strip().lstrip('v')}    1.14.7

README Documents The Envoy Image The Code Uses
    ${deployment}=    Get File    ${ROOT}${/}controllers${/}deployment.go
    ${image}=    Get Regexp Matches    ${deployment}    img := "(envoyproxy/envoy:[^"]+)"    1
    Should Not Be Empty    ${image}
    Repo File Should Contain    README.md    `${image}[0]`
    Repo File Should Not Contain    README.md    envoy-alpine:v1.16.5

Generated Envoy Config Is Accepted By The Default Envoy Image
    [Documentation]    Includes UDP ports: the UDP proxy must be a listener filter, not a filter chain.
    [Tags]    slow    docker
    ${docker}=    Run Process    docker    info    stderr=STDOUT
    Skip If    ${docker.rc} != 0    Docker is not available
    ${result}=    Command Should Succeed    make    validate-envoy-config    timeout=15 min
    Should Contain    ${result.stdout}    udp_and_tcp.yaml' OK

Dependabot Watches Both Go Modules, Dockerfiles And Actions
    Repo File Should Contain    .github/dependabot.yml    directory: /coredns-plugin
    Repo File Should Contain    .github/dependabot.yml    package-ecosystem: docker
    Repo File Should Contain    .github/dependabot.yml    package-ecosystem: github-actions


*** Keywords ***
Get Toolchain
    [Arguments]    ${path}
    ${content}=    Get File    ${ROOT}${/}${path}
    ${match}=    Get Regexp Matches    ${content}    (?m)^toolchain go(\\S+)$    1
    Should Not Be Empty    ${match}    msg=${path} has no toolchain directive
    RETURN    ${match}[0]

Version Should Be At Least
    [Arguments]    ${actual}    ${minimum}
    ${ok}=    Evaluate    tuple(int(x) for x in $actual.split('.')) >= tuple(int(x) for x in $minimum.split('.'))
    Should Be True    ${ok}    msg=${actual} < ${minimum}
