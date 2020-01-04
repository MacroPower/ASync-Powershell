function ForEach-Object-Async {
  <#
    .SYNOPSIS
    ForEach-Object, but asynchronous.

    .DESCRIPTION
    Based on Start-Parallel, but behaves more similarly to a traditional ForEach. Syntax is identical, and variables are passed to and from each runspace.

    .PARAMETER MaxThreads
    This is the maximum number of runspaces (threads) to run at any given time. The default value is 50.

    .PARAMETER MilliSecondsDelay
    When looping waiting for commands to complete, this value introduces a delay between each check to prevent 
    excessive CPU utilization. The default value is 200ms. For long runnng processes, this value can be increased. 

    .EXAMPLE
    $x = 0; 1..10 | ForEach-Object-Async { $x++ }; $x
    Returns 10

    .EXAMPLE
    $x = 0; 1..10 | ForEach-Object-Async { $x++; Start-Sleep 5 }; $x
    Returns 1
  #>

  Param (
    [Parameter(Mandatory, ValueFromPipeline)][Object]$InputObject,
    [Parameter(Mandatory,Position=0)][ScriptBlock]$Scriptblock,
    [int]$MaxThreads = 50,
    [int]$MilliSecondsDelay = 200
  )
  Begin {
    $taskList     = @()
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $MaxThreads)
    $runspacePool.Open()
    
    $paramList = (Get-Command -Name $PSCmdlet.MyInvocation.InvocationName).Parameters
    
    $ExcludeVarsScript = { 
      $paramList.Keys + (
        [psobject].Assembly.GetType('System.Management.Automation.SpecialVariables').GetFields('NonPublic,Static') | .{
          Process {
            if ($_.FieldType -eq ([string])) {
              $_.GetValue($null)
            }
          }
        }
      ) + @(
        'FormatEnumerationLimit',
        'MaximumAliasCount',
        'MaximumDriveCount',
        'MaximumErrorCount',
        'MaximumFunctionCount',
        'MaximumVariableCount',
        'PGHome',
        'PGSE',
        'PGUICulture',
        'PGVersionTable',
        'PROFILE',
        'PSSessionOption',
        'psISE',
        'runspacePool',
        'newThread',
        'paramList',
        'psUnsupportedConsoleApplications',
        'ExcludeVars',
        'ExcludeVarsScript',
        'taskList',
        'handle',
        'hash',
        'endTasks'
      )
    }
    
    $Scriptblock = [ScriptBlock]::Create($Scriptblock.ToString() + "`n" + '$ExcludeVars=' + $ExcludeVarsScript.ToString()  + "`n" + {
        Get-Variable | .{
          Process {
            if ($_.Name -notin $ExcludeVars) {
              $hash.($_.Name) = $_.Value
            }
          }
        }
    }.ToString())
    
    $endTasks = {
      $taskList | .{ 
        Process { 
          if ($_.Handle.IsCompleted) {
            $_.Hash.GetEnumerator() | .{
              Process { 
                Write-Verbose ('Setting {0} to {1}' -f $_.Name, $_.Value)
                Set-Variable -Name $_.Name -Value $_.Value -Scope Script
              }
            }
            $_.Thread.EndInvoke($_.Handle)
            $_.Thread.Dispose()
            $_.Thread = $_.Handle = $Null
            $_.Hash = $Null
          }
        }
      }
    }
  }
  Process {
    
    $hash = [hashtable]@{}
    $newThread = [powershell]::Create().AddScript($Scriptblock)
    $newThread.Runspace.SessionStateProxy.SetVariable('_',$InputObject)
    $newThread.Runspace.SessionStateProxy.SetVariable('hash',$hash)
    
    $ExcludeVars = Invoke-Command -ScriptBlock $ExcludeVarsScript
    
    Get-Variable | .{
      Process {
        if ($_.Name -notin $ExcludeVars) {
          Write-Verbose ('Passing {0} - {1}' -f $_.Name, $_.Value)
          $newThread.Runspace.SessionStateProxy.SetVariable($_.Name,$_.Value)
        }
      }
    }
    
    $handle = $newThread.BeginInvoke()
    $taskList += New-Object -TypeName psobject -Property @{
      'Handle' = $handle
      'Thread' = $newThread
      'Hash'   = $hash
    }
    
    Start-Sleep -Milliseconds $MilliSecondsDelay
    
    Invoke-Command -ScriptBlock $endTasks
  }
  End {
    While ($TaskList.where{$_.Handle})
    {
      Invoke-Command -ScriptBlock $endTasks
      Start-Sleep -Milliseconds $MilliSecondsDelay
    } 
    $null = $RunspacePool.Close()   
    $null = $RunspacePool.Dispose() 
    [gc]::Collect()
  }
}
