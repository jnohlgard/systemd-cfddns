FROM fedora:latest
LABEL maintainer="Joakim Nohlgård <joakim@nohlgard.se>"

COPY cfupdater.sh /
ENV CF_API_TOKEN_FILE=/run/secrets/cf_dns_api_token
ENTRYPOINT ["/bin/sh", "/cfupdater.sh"]
