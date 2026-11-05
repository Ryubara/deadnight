#!/usr/bin/env bash
# Shared by deploy/web/deploy.sh, deploy/server/deploy.sh and deploy/backend/deploy.sh (sourced, never run): the upload
# with a bounded number of attempts, and the reads of the service's newest deployment.
#
# Why. A deploy job failed on 2026-11-05 with Railway's `failed to fetch snapshot` / `Deploy failed: Failed to build an
# image`, and a rerun of the same job passed (run 42044278283, #1269). The service had already been given a deployment
# (it said FAILED), so the cause was on Railway's side. A second `railway up` is the cure, but never at the price of two
# deployments of one service at once: the first one may be still building when the CLI's stream breaks, and a second
# upload would replace it half way. So an attempt is repeated only when this holds, read from the service itself:
#
#   - the failed attempt left no new deployment (the upload never got there), or the one it left is FAILED / CRASHED /
#     REMOVED (it is over; the snapshot case); and
#   - there is time: the whole script has $RAILWAY_DEPLOY_SECONDS (CI sets it below the job's `timeout-minutes`, with
#     room for the setup before the script), an attempt may take $RAILWAY_UP_ATTEMPT_SECONDS (600) at most, and the
#     time for the wait for the health check ($RAILWAY_UP_WAIT_RESERVE, 180 s) is kept back from the last attempt.
#
# A failed attempt whose deployment is SUCCESS or still going (BUILDING, DEPLOYING, QUEUED ...) is not repeated: the
# function returns 0 and the script's own wait for the deployment follows it, and fails the job if it ends badly. When the
# CLI cannot list the deployments, nothing proves no deployment is alive, so the failure stands.
#
# A script with no project to deploy to is refused before anything is uploaded: with neither $RAILWAY_TOKEN nor a linked
# project, `railway up` on a folder named `stage` made a new Railway project called `stage` in the account (twice by
# 2026-11-05, once by hand and once in a probe of these scripts).
#
# What stays as it was: a successful deploy runs `railway up` once, the same way; a real build failure (a Dockerfile that
# does not build) fails after $RAILWAY_UP_ATTEMPTS (3) attempts with every attempt's log in the job, instead of after one.
#
# Knobs (all optional): RAILWAY_DEPLOY_SECONDS (no limit when unset), RAILWAY_UP_ATTEMPTS, RAILWAY_UP_ATTEMPT_SECONDS,
# RAILWAY_UP_MIN_ATTEMPT_SECONDS (120: a retry that would get less than this is not started), RAILWAY_UP_PAUSE (20 s,
# times the attempt number), RAILWAY_UP_WAIT_RESERVE, RAILWAY_POLL_SECONDS (10, the wait loops).

RAILWAY_DEPLOY_T0=$SECONDS

# railway_time_left: the seconds the script may still use, never below 0 (a day when RAILWAY_DEPLOY_SECONDS is not set).
railway_time_left() {
    local left=$(( ${RAILWAY_DEPLOY_SECONDS:-86400} - (SECONDS - RAILWAY_DEPLOY_T0) ))
    if [ "$left" -gt 0 ]; then echo "$left"; else echo 0; fi
}

# railway_newest <service>: "<id> <status>" of the service's newest deployment, or nothing and a failure when the CLI
# does not answer (the list is newest first; its first top-level "id" and "status" are the ones at four spaces).
railway_newest() {
    local list id status
    list=$(railway deployment list --service "$1" --json 2>/dev/null) || return 1
    id=$(printf '%s\n' "$list" | grep -m1 '^    "id"' | cut -d'"' -f4) || true
    status=$(printf '%s\n' "$list" | grep -m1 '^    "status"' | cut -d'"' -f4) || true
    [ -n "$id" ] && [ -n "$status" ] || return 1
    echo "$id $status"
}

# railway_status <service>: the newest deployment's status, or nothing when it cannot be read (the wait loops ask again).
railway_status() {
    local newest
    newest=$(railway_newest "$1") || return 0
    echo "${newest#* }"
}

# railway_up_retry <service> <message> <stage folder>: `railway up` as the three scripts ran it, repeated as described above.
# Returns 0 when the upload went through, or when it failed but the service holds a deployment that is live or going;
# returns the last attempt's exit code otherwise.
railway_up_retry() {
    local service=$1 message=$2 stage=$3
    local attempts=${RAILWAY_UP_ATTEMPTS:-3} per=${RAILWAY_UP_ATTEMPT_SECONDS:-600} pause=${RAILWAY_UP_PAUSE:-20}
    local reserve=${RAILWAY_UP_WAIT_RESERVE:-180} floor=${RAILWAY_UP_MIN_ATTEMPT_SECONDS:-120}
    local n limit left before after code=0 note

    if [ -z "${RAILWAY_TOKEN:-}" ] && ! railway status >/dev/null 2>&1; then
        echo "::error title=No Railway project::neither RAILWAY_TOKEN is set nor a project linked (railway link): without one, railway up makes a new project named after the folder" >&2
        return 2
    fi

    for n in $(seq 1 "$attempts"); do
        left=$(railway_time_left)
        limit=$(( left - reserve ))
        [ "$limit" -le "$per" ] || limit=$per
        if [ "$limit" -lt "$floor" ]; then
            if [ "$n" -gt 1 ]; then
                echo "::error title=Railway upload failed::no time for attempt $n: ${left}s of the job's budget are left and an attempt needs $floor s plus $reserve s to wait for the health check" >&2
                return "$code"
            fi
            limit=$floor
        fi

        before=$(railway_newest "$service") || before=""
        before=${before%% *}
        code=0
        timeout "$limit" railway up "$stage" --path-as-root --service "$service" --ci --message "$message" || code=$?
        [ "$code" != 0 ] || return 0

        note="exit code $code"
        [ "$code" != 124 ] || note="stopped after $limit s"
        echo "::warning title=railway up failed (attempt $n of $attempts)::$note"

        # What did the failed attempt leave on the service? Never upload again over a deployment that is alive.
        if [ -z "$before" ]; then
            echo "::error title=Railway upload failed::could not list the service's deployments before the attempt, so a deployment it made cannot be told from an old one; not repeated" >&2
            return "$code"
        fi
        after=$(railway_newest "$service") || {
            echo "::error title=Railway upload failed::could not list the service's deployments after the attempt, so it cannot be shown that none is alive; not repeated" >&2
            return "$code"
        }
        if [ "${after%% *}" != "$before" ]; then
            case ${after#* } in
                SUCCESS | INITIALIZING | BUILDING | DEPLOYING | QUEUED | WAITING | NEEDS_APPROVAL)
                    echo "the attempt left deployment ${after%% *} (${after#* }): not uploading again, waiting for it"
                    return 0
                    ;;
                FAILED | CRASHED | REMOVED | REMOVING | SKIPPED)
                    echo "the attempt left deployment ${after%% *} (${after#* }), which is over"
                    ;;
                *)
                    echo "::error title=Railway upload failed::the attempt left deployment ${after%% *} in status ${after#* }, which is not known to be over; not repeated" >&2
                    return "$code"
                    ;;
            esac
        else
            echo "the attempt left no deployment"
        fi

        [ "$n" -lt "$attempts" ] || break
        sleep $(( pause * n ))
    done
    echo "::error title=Railway upload failed::railway up failed $n times (the last: $note)" >&2
    return "$code"
}
