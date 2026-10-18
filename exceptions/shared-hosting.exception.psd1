@{
    # Name of the exception, used for identification in reports and logs.
    Name = 'Shared hosting zones'

    # Enabled declarations contribute their keys to every Run; disabling a
    # declaration restores enforcement for its keys on the next Run.
    Enabled = $true

    # Derived wildcard recovery turns a source pattern that names one tenant of a
    # shared zone into a block on the whole zone. The LolRMM row
    # 'pdqinstallers.*.r2.cloudflarestorage.com' recovers to
    # '*.r2.cloudflarestorage.com', which would block every Cloudflare R2 bucket
    # rather than the single bucket the source named. The wildcard is withheld.
    ExceptionKey = @('domain:*.r2.cloudflarestorage.com')
}
