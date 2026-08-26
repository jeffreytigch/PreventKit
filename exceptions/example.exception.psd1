@{
    # Name of the exception, used for identification in reports and logs.
    Name = 'Example'

    # Enabled declarations contribute their keys to every Run; disabling a
    # declaration restores enforcement for its keys on the next Run.
    Enabled = $false

    # Exception keys matched by this exception. Each key is 'service:<serviceId>'
    # or 'domain:<value>'. Matching entries leave the desired state and are never
    # enforced (no allow rule is created).
    ExceptionKey = @('service:lolrmm/Example')
}
