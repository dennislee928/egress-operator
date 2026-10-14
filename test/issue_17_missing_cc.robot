*** Settings ***
Documentation       Issue #17: `make run` failed with "cgo: exec /missing-cc" on machines without a C compiler.
...                 controller-gen loads packages through `go list`, which needs a C compiler when cgo is on.
...                 The Makefile now installs and runs a pinned controller-gen with CGO_ENABLED=0.
...                 https://github.com/monzo/egress-operator/issues/17
Resource            resources/common.resource
Test Tags           issue-17


*** Test Cases ***
Controller-gen Fails Without A C Compiler When Cgo Is Enabled
    [Documentation]    Reproduces the reported failure mode so the test below is meaningful.
    Command Should Succeed    make    controller-gen    timeout=10 min
    ${result}=    Command Should Fail    bin/controller-gen    object:headerFile\=./hack/boilerplate.go.txt
    ...    paths\=./...    env:CC=/missing-cc    env:CGO_ENABLED=1    timeout=5 min
    Should Contain    ${result.stdout}    missing-cc

Make Generate And Manifests Work Without A C Compiler
    Command Should Succeed    make    generate    manifests    env:CC=/missing-cc    timeout=10 min

Makefile Uses The Pinned Controller-gen Rather Than One On PATH
    Repo File Should Contain    Makefile    CONTROLLER_TOOLS_VERSION ?= v0.17.0
    Repo File Should Not Contain    Makefile    which controller-gen
