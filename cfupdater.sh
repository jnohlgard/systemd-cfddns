#!/bin/sh

set -euo pipefail

# Create an API token with edit Zone DNS permission on https://dash.cloudflare.com/profile/api-tokens
# Zone ID can be found in the "Overview" tab of your domain
if [ -z "${CF_API_TOKEN_FILE-}" ]; then
  >&2 printf 'Missing CF_API_TOKEN_FILE environment variable\n'
  exit 1
fi
if [ -z "${CF_ZONE_ID-}" ]; then
  >&2 printf 'Missing CF_ZONE_ID environment variable\n'
  exit 1
fi

update_ipv4=
update_ipv6=
while getopts "46" arg; do
  case $arg in
    4)
      update_ipv4=yes
      ;;
    6)
      update_ipv6=yes
      ;;
  esac
done
shift "$((OPTIND-1))"

if [ $# -ne 1 ]; then
  >&2 printf 'Wrong number of arguments\n'
  printf 'Usage: %s [-4] [-6] <record_name>\n' "$0"
  printf 'Update record_name via Cloudflare API\n'
  exit 1
fi

if [ -z "${update_ipv4}${update_ipv6}" ]; then
  >&2 printf 'You must specify at least one of -4 -6\n'
  exit 1
fi

api_token=$(cat ${CF_API_TOKEN_FILE})
zone_identifier=${CF_ZONE_ID}
record_name=$1; shift

maybe_update_record() {
  local record_type=$1; shift
  local record_name=$1; shift
  local new_content=$1; shift

  # Get the current DNS record from API
  local existing_record=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${zone_identifier}/dns_records?name=${record_name}&type=${record_type}" -H "Authorization: Bearer ${api_token}" -H "Accept: application/json")

  # We are avoiding any extra tools like jq, so we have to grep the json source
  if printf '%s' "${existing_record}" | grep -q '"count":0'; then
    >&2 printf '[Cloudflare DDNS] Record does not exist: %s type %s\n' "${record_name}" "${record_type}"
    exit 1
  fi

  # NB: This regex will fail if the string contains escaped quotes, which we don't expect in an A, AAAA record.
  old_content=$(printf '%s' "${existing_record}" | sed -n -e 's/^.*"content":[^"]*"\([^"]*\)".*$/\1/p')

  if [ "${new_content}" = "${old_content}" ]; then
    printf '[Cloudflare DDNS] IP has not changed.\n'
    return 0
  fi

  record_identifier=$(printf '%s' "${existing_record}" | sed -n -e 's/^.*"id":[^"]*"\([^"]*\)".*$/\1/p')

  # Call the DNS update API
  result=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/${zone_identifier}/dns_records/${record_identifier}" -H "Authorization: Bearer ${api_token}" -H "Content-Type: application/json" -H "Accept: application/json" --data "{\"type\":\"${record_type}\",\"name\":\"${record_name}\",\"content\":\"${new_content}\"}")

  if printf '%s' "${result}" | grep -q '"success":false'; then
    >&2 printf '[Cloudflare DDNS] Update failed for %s type %s (id="%s")\nServer said: %s\n' "${record_name}" "${record_type}" "${record_identifier}" "${result}"
    return 1
  fi
  printf '[Cloudflare DDNS] Success! Updated %s type %s: "%s" (was: "%s").\n' "${record_name}" "${record_type}" "${new_content}" "${old_content}"
}

printf '[Cloudflare DDNS] Check Initiated\n'

url_v4=https://ipv4.icanhazip.com/
url_v6=https://ipv6.icanhazip.com/

status_v4=0
current_v4=
if [ "${update_ipv4}" = yes ]; then
  if ! current_v4=$(curl -s "${url_v4}"); then
    status_v4=1
    >&2 printf 'Unable to get current IPv4 address from %s\n' "${url_v4}"
  else
    maybe_update_record A "${record_name}" "${current_v4}"
    status_v4=$?
  fi
fi

status_v6=0
current_v6=
if [ "${update_ipv6}" = yes ]; then
  if ! current_v6=$(curl -s "${url_v6}"); then
    status_v6=1
    >&2 printf 'Unable to get current IPv6 address from %s\n' "${url_v6}"
  else
    maybe_update_record AAAA "${record_name}" "${current_v6}"
    status_v6=$?
  fi
fi

if [ ${status_v4} -ne 0 ]; then
  exit ${status_v4}
fi
if [ ${status_v6} -ne 0 ]; then
  exit ${status_v6}
fi
