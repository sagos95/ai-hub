#!/bin/bash
# TestOps high-level CLI — удобные подкоманды поверх testops.sh
# Usage: ./testops-api.sh <command> [args...]
#
# Commands:
#   projects [query]                        — поиск проектов
#   testcases <projectId> [rql]             — поиск тест-кейсов (AQL)
#   testcase <id>                           — обзор тест-кейса
#   testcase-scenario <id>                  — сценарий тест-кейса (шаги)
#   testcase-history <id>                   — история запусков тест-кейса
#   launches <projectId> [rql]              — поиск запусков (AQL)
#   launch <id>                             — детали запуска
#   launch-stats <id>                       — статистика запуска
#   defects <projectId> [nameFilter]        — поиск дефектов
#   defect <id>                             — детали дефекта
#   jobs [projectId]                        — поиск джобов
#   job <id>                                — детали джоба
#   testplans <projectId> [name]            — поиск тест-планов
#   testplan <id>                           — детали тест-плана
#   run-testplan <id> <name> [description]  — запуск тест-плана

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTOPS="$SCRIPT_DIR/testops.sh"

CMD="${1:-help}"
shift 2>/dev/null || true

urlencode() {
    python3 -c "import urllib.parse; print(urllib.parse.quote('$1', safe=''))"
}

case "$CMD" in

    # ── Projects ──────────────────────────────────────────────
    projects)
        QUERY="${1:-}"
        PARAMS="page=0&size=50&sort=name,ASC&v2=true"
        [[ -n "$QUERY" ]] && PARAMS="query=$(urlencode "$QUERY")&$PARAMS"
        "$TESTOPS" GET "/project?$PARAMS"
        ;;

    # ── Test Cases ────────────────────────────────────────────
    testcases)
        PROJECT_ID="$1"; shift 2>/dev/null || true
        RQL="${1:-}"
        if [[ -z "$PROJECT_ID" ]]; then
            echo "Usage: testops-api.sh testcases <projectId> [rql]" >&2
            exit 1
        fi
        PARAMS="projectId=${PROJECT_ID}&deleted=false&page=0&size=20&sort=id,DESC"
        if [[ -n "$RQL" ]]; then
            PARAMS="${PARAMS}&rql=$(urlencode "$RQL")"
        else
            PARAMS="${PARAMS}&rql="
        fi
        "$TESTOPS" GET "/rs/testcase/__search?$PARAMS"
        ;;

    testcase)
        ID="$1"
        [[ -z "$ID" ]] && { echo "Usage: testops-api.sh testcase <id>" >&2; exit 1; }
        "$TESTOPS" GET "/rs/testcase/${ID}/overview"
        ;;

    testcase-scenario)
        ID="$1"
        [[ -z "$ID" ]] && { echo "Usage: testops-api.sh testcase-scenario <id>" >&2; exit 1; }
        "$TESTOPS" GET "/rs/testcase/${ID}/step"
        ;;

    testcase-history)
        ID="$1"
        [[ -z "$ID" ]] && { echo "Usage: testops-api.sh testcase-history <id>" >&2; exit 1; }
        "$TESTOPS" GET "/testcase/${ID}/history?page=0&size=20&sort=createdDate,DESC"
        ;;

    # ── Launches ──────────────────────────────────────────────
    launches)
        PROJECT_ID="$1"; shift 2>/dev/null || true
        RQL="${1:-}"
        if [[ -z "$PROJECT_ID" ]]; then
            echo "Usage: testops-api.sh launches <projectId> [rql]" >&2
            exit 1
        fi
        PARAMS="projectId=${PROJECT_ID}&page=0&size=20&sort=created_date,DESC"
        if [[ -n "$RQL" ]]; then
            PARAMS="${PARAMS}&rql=$(urlencode "$RQL")"
        else
            PARAMS="${PARAMS}&rql="
        fi
        "$TESTOPS" GET "/launch/__search?$PARAMS"
        ;;

    launch)
        ID="$1"
        [[ -z "$ID" ]] && { echo "Usage: testops-api.sh launch <id>" >&2; exit 1; }
        "$TESTOPS" GET "/launch/${ID}"
        ;;

    launch-stats)
        ID="$1"
        [[ -z "$ID" ]] && { echo "Usage: testops-api.sh launch-stats <id>" >&2; exit 1; }
        "$TESTOPS" GET "/launch/${ID}/statistic"
        ;;

    # ── Defects ───────────────────────────────────────────────
    defects)
        PROJECT_ID="$1"; shift 2>/dev/null || true
        NAME_FILTER="${1:-}"
        if [[ -z "$PROJECT_ID" ]]; then
            echo "Usage: testops-api.sh defects <projectId> [nameFilter]" >&2
            exit 1
        fi
        PARAMS="projectId=${PROJECT_ID}&page=0&size=20&sort=closed,created_date,DESC"
        [[ -n "$NAME_FILTER" ]] && PARAMS="${PARAMS}&nameFilter=$(urlencode "$NAME_FILTER")"
        "$TESTOPS" GET "/defect?$PARAMS"
        ;;

    defect)
        ID="$1"
        [[ -z "$ID" ]] && { echo "Usage: testops-api.sh defect <id>" >&2; exit 1; }
        "$TESTOPS" GET "/defect/${ID}"
        ;;

    # ── Jobs ──────────────────────────────────────────────────
    jobs)
        PROJECT_ID="${1:-}"
        PARAMS="page=0&size=20&sort=name"
        [[ -n "$PROJECT_ID" ]] && PARAMS="projectId=${PROJECT_ID}&$PARAMS"
        "$TESTOPS" GET "/job?$PARAMS"
        ;;

    job)
        ID="$1"
        [[ -z "$ID" ]] && { echo "Usage: testops-api.sh job <id>" >&2; exit 1; }
        "$TESTOPS" GET "/job/${ID}"
        ;;

    # ── Test Plans ────────────────────────────────────────────
    testplans)
        PROJECT_ID="$1"; shift 2>/dev/null || true
        NAME="${1:-}"
        if [[ -z "$PROJECT_ID" ]]; then
            echo "Usage: testops-api.sh testplans <projectId> [name]" >&2
            exit 1
        fi
        PARAMS="projectId=${PROJECT_ID}&page=0&size=20"
        [[ -n "$NAME" ]] && PARAMS="${PARAMS}&name=$(urlencode "$NAME")"
        "$TESTOPS" GET "/testplan?$PARAMS"
        ;;

    testplan)
        ID="$1"
        [[ -z "$ID" ]] && { echo "Usage: testops-api.sh testplan <id>" >&2; exit 1; }
        "$TESTOPS" GET "/testplan/${ID}"
        ;;

    run-testplan)
        ID="$1"; shift 2>/dev/null || true
        NAME="$1"; shift 2>/dev/null || true
        DESC="${1:-}"
        if [[ -z "$ID" || -z "$NAME" ]]; then
            echo "Usage: testops-api.sh run-testplan <id> <name> [description]" >&2
            exit 1
        fi
        BODY="{\"name\":\"$NAME\""
        [[ -n "$DESC" ]] && BODY="${BODY},\"description\":\"$DESC\""
        BODY="${BODY}}"
        "$TESTOPS" POST "/testplan/${ID}/run" "$BODY"
        ;;

    # ── Help ──────────────────────────────────────────────────
    help|--help|-h|*)
        echo "TestOps CLI — Allure TestOps API wrapper"
        echo ""
        echo "Usage: $(basename "$0") <command> [args...]"
        echo ""
        echo "Commands:"
        echo "  projects [query]                        Search projects"
        echo "  testcases <projectId> [rql]             Search test cases (AQL)"
        echo "  testcase <id>                           Get test case overview"
        echo "  testcase-scenario <id>                  Get test case scenario (steps)"
        echo "  testcase-history <id>                   Get test case run history"
        echo "  launches <projectId> [rql]              Search launches (AQL)"
        echo "  launch <id>                             Get launch details"
        echo "  launch-stats <id>                       Get launch statistics"
        echo "  defects <projectId> [nameFilter]        Search defects"
        echo "  defect <id>                             Get defect details"
        echo "  jobs [projectId]                        Search jobs"
        echo "  job <id>                                Get job details"
        echo "  testplans <projectId> [name]            Search test plans"
        echo "  testplan <id>                           Get test plan details"
        echo "  run-testplan <id> <name> [description]  Run a test plan"
        echo ""
        echo "Environment:"
        echo "  TESTOPS_URL    — base URL (e.g. https://your.qatools.cloud)"
        echo "  TESTOPS_TOKEN  — API token"
        ;;
esac
