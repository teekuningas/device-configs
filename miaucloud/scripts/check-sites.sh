#!/bin/sh
# Post-deploy check for miaucloud. Expected codes are what the site returns when
# it is healthy — 401 means basicauth is up, 400 means PostgREST is rejecting an
# unauthenticated request (correct), 302 is Logto's admin redirect.
check() {
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "https://$1/" 2>/dev/null)
  if [ "$code" = "$2" ]; then printf '  ok    %-34s %s\n' "$1" "$code"
  else printf '  FAIL  %-34s got %s, expected %s\n' "$1" "${code:-none}" "$2"; fi
}
echo "teekuningas.net"
check teekuningas.net                 200
check www.teekuningas.net             200
check meggie.teekuningas.net          200
check vaatteet.teekuningas.net        200
check clothinv-postgrest.teekuningas.net 400
check soitbegins.teekuningas.net      200
check teehetki.teekuningas.net        401
check openwebui.teekuningas.net       200
check auth-api.teekuningas.net        302
check auth-ui.teekuningas.net         302
check kingofsweden.info               200
check raven.teekuningas.net           200
echo "suvannossa.fi"
check suvannossa.fi                   200
check www.suvannossa.fi               200
check pallo.suvannossa.fi             200
check sartre.suvannossa.fi            200
check imdb.suvannossa.fi              200
check luonto.suvannossa.fi            200
