Function Invoke-DependencyScript {
    <#
    .SYNOPSIS
        Invoke a dependency script

    .DESCRIPTION
        Invoke a dependency script

        See Get-Help about_PSDepend for more information.

    .PARAMETER Dependency
        Dependency object from Get-Dependency.

    .PARAMETER PSDependTypePath
        Specify a PSDependMap.psd1 file that maps DependencyTypes to their scripts.

        This defaults to the PSDependMap.psd1 in the PSDepend module folder

    .PARAMETER Tags
        Only test dependencies that are tagged with all of the specified Tags (-and, not -or)

    .PARAMETER PSDependAction
        

    .EXAMPLE
        Get-Dependency -Path C:\requirements.psd1 | Import-Dependency

        Get dependencies from C:\requirements.psd1 and import them

    .LINK
        about_PSDepend

    .LINK
        about_PSDepend_Definitions

    .LINK
        Get-Dependency

    .LINK
        Get-PSDependType

    .LINK
        Invoke-PSDepend

    .LINK
        https://github.com/RamblingCookieMonster/PSDepend
    #>
    [cmdletbinding()]
    Param(
        [parameter( ValueFromPipeline = $True,
                    ParameterSetName='Map',
                    Mandatory = $True)]
        [PSTypeName('PSDepend.Dependency')]
        [psobject[]]$Dependency,

        [validatescript({Test-Path -Path $_ -PathType Leaf -ErrorAction Stop})]
        [string]$PSDependTypePath = $(Join-Path $ModuleRoot PSDependMap.psd1),

        [string[]]$PSDependAction,

        [string[]]$Tags
    )
    Begin
    {
        # This script reads a depend.psd1, installs dependencies as defined
        Write-Verbose "Running Invoke-DependencyScript with ParameterSetName '$($PSCmdlet.ParameterSetName)' and params: $($PSBoundParameters | Out-String)"
    }
    Process
    {
        Write-Verbose "Dependencies:`n$($Dependency | Out-String)"

        #Get definitions, and dependencies in this particular psd1
        $DependencyDefs = Get-PSDependScript
        $TheseDependencyTypes = @( $Dependency.DependencyType | Sort-Object -Unique )

        #Build up hash, we call each dependencytype script for applicable dependencies
        foreach($DependencyType in $TheseDependencyTypes)
        {
            $DependencyScript = $DependencyDefs.$DependencyType
            if(-not $DependencyScript)
            {
                Write-Error "DependencyType $DependencyType is not defined in PSDependMap.psd1"
                continue
            }
            $TheseDependencies = @( $Dependency | Where-Object {$_.DependencyType -eq $DependencyType})

            #Define params for the script
            #Each dependency type can have a hashtable to splat.
            $RawParameters = Get-Parameter -Command $DependencyScript
            $ValidParamNames = $RawParameters.Name
            if($ValidParamNames -notcontains 'PSDependAction')
            {
                Write-Error "No PSDependAction found on PSDependScript [$DependencyScript]. Skipping [$($Dependency.DependencyName)]"
                continue
            }
            [string[]]$ValidPSDependActions = $RawParameters | Where {$_.Name -like 'PSDependAction'} | Select -ExpandProperty ValidateSetValues -ErrorAction SilentlyContinue
            [string[]]$PSDependActions = foreach($Action in $PSDependAction)
            {
                if($ValidPSDependActions -contains $Action) {$Action}
                else
                {
                    Write-Error "Skipping PSDependAction [$Action] for dependency [$($Dependency.DependencyName)]. Valid actions: [$ValidPSDependActions]"
                }
            }

            if($PSDependActions -contains 'Test' -and ( $PSDependActions -contains 'Import' -or $PSDependActions -contains 'Install'))
            {
                Write-Error "Removing [Test] from PSDependActions.  The Test action must run on its own."
                $PSDependActions = $PSDependActions | Where {$_ -ne 'Test'}
            }

            foreach($ThisDependency in $TheseDependencies)
            {
                #Parameters for dependency types.  Only accept valid params...
                if($ThisDependency.Parameters.keys.count -gt 0)
                {
                    $splat = @{}
                    foreach($key in $ThisDependency.Parameters.keys)
                    {
                        if($ValidParamNames -contains $key)
                        {
                            $splat.Add($key, $ThisDependency.Parameters.$key)
                        }
                        else
                        {
                            Write-Warning "Parameter [$Key] with value [$($ThisDependency.Parameters.$Key)] is not a valid parameter for [$DependencyType], ignoring.  Valid params:`n[$ValidParamNames]"
                        }
                    }
                    if($splat.ContainsKey('PSDependAction'))
                    {
                        $Splat['PSDependAction'] = $PSDependActions
                    }
                    else
                    {
                        $Splat.add('PSDependAction', $PSDependActions)
                    }
                }
                else
                {
                    $splat = @{PSDependAction = $PSDependActions}
                }

                #Define params for the script
                $splat.add('Dependency', $ThisDependency)

                # PITA, but tasks can run two ways, each different than typical dependency scripts
                if($PSDependActions -contains 'Install' -and $DependencyType -eq 'Task')
                {
                    foreach($TaskScript in $ThisDependency.Target)
                    {
                        if( Test-Path $TaskScript -PathType Leaf)
                        {
                            . $TaskScript @splat
                        }
                        else
                        {
                            Write-Error "Could not process task [$TaskScript].`nAre connectivity, privileges, and other needs met to access it?"
                        }
                    }
                }
                else
                {
                    . $DependencyScript @splat
                }
            }
        }
    }
}
