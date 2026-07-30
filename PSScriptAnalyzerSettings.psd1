@{
    # PSScriptAnalyzer configuration for the PowerShell installer.
    #
    # Only rules that genuinely do not apply to an interactive console
    # installer are excluded, each with the reason it is exempt.

    IncludeDefaultRules = $true

    ExcludeRules = @(
        # The installer *is* a console UI: coloured, ordered output for a human
        # is the product, not a side effect. Write-Output would break the
        # layout and pollute the pipeline of anything that calls us.
        'PSAvoidUsingWriteHost'

        # Our New-* functions build in-memory objects (catalog rows, config,
        # manifest hashtables) and touch nothing on disk. Every function that
        # does write already implements SupportsShouldProcess.
        'PSUseShouldProcessForStateChangingFunctions'

        # "Remote" skill bundles publish their install command as a shell
        # snippet in README.md; it has to be executed verbatim, exactly as
        # install.sh does with `eval`.
        'PSAvoidUsingInvokeExpression'
    )
}
