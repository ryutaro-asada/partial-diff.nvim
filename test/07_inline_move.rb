<<<<<<< FROM
# Reordering within a single line (intra-line move)
ORDER = [:alpha, :beta, :gamma, :delta, :epsilon, :zeta]
ROUTE = "home -> search -> details -> cart -> checkout -> done"
ARGS = parse(input, verbose: true, color: false, retries: 3)
=======
# Reordering within a single line (intra-line move)
ORDER = [:gamma, :alpha, :beta, :delta, :epsilon, :zeta]
ROUTE = "home -> search -> cart -> details -> checkout -> done"
ARGS = parse(input, color: false, retries: 3, verbose: true)
>>>>>>> TO
