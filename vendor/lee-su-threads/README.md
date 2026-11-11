Source: https://github.com/meettomorrow/lee-su-threads
Revision: db0476fc10cc6a738c6a6eb49ed2f1dd89174419
License: MIT (see LICENSE)

profileParser.js, dateParser.js and location-flags.json are unmodified upstream files. Test fixtures
are copied from the same revision. The native bridge adapts the upstream session
token scanning and About This Profile request. No authentication tokens are
returned to native code, exported, or sent to a service other than Threads.

The upstream flag table includes country/territory names from
https://github.com/stefangabos/world_countries plus upstream aliases and overrides.
The native formatter matches complete names across the table's five languages,
preserves the original region text, and adds the missing 臺灣/台湾 aliases.
