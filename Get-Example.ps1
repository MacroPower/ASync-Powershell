function Get-Example 
{
  [CmdletBinding()]
  Param(
    [String][Parameter(ValueFromPipeline)]$Example,
    [Switch]$ASync
  )
  Begin {
    $paramList = (Get-Command -Name $PSCmdlet.MyInvocation.InvocationName).Parameters | .{
      Process {
        Get-Variable -Name $_.Values.Name -ErrorAction SilentlyContinue
      }
    }
    $Jobs = [System.Collections.ArrayList]@()
  }
  Process {
    $ScriptBlock = {
      Write-Output ('This is my command ' + $Example)
      
      #And this is how long it takes to run.
      Start-Sleep -Seconds (Get-Random -Minimum 4 -Maximum 6)
    }
    
    if($ASync) 
    {
      $newRunspace = [runspacefactory]::CreateRunspace()
      $newRunspace.ApartmentState = 'STA'
      $newRunspace.ThreadOptions = 'ReuseThread'          
      $newRunspace.Open()
      $paramList | .{
        Process {
          $newRunspace.SessionStateProxy.SetVariable($_.Name,$_.Value)
        }
      }
      $PowerShell = [PowerShell]::Create().AddScript($ScriptBlock)
      $PowerShell.Runspace = $newRunspace
      [void]$Jobs.Add((
          [pscustomobject]@{
            PowerShell = $PowerShell
            Runspace   = $PowerShell.BeginInvoke()
          }
      ))
    } else 
    {
      Invoke-Command -ScriptBlock $ScriptBlock
    }
  }
  End {
    do {
      $JobsCompleted = [System.Collections.ArrayList]@()
      $Jobs | .{
        Process {
          if ($_.Runspace.isCompleted) 
          {
            $_.Powershell.EndInvoke($_.Runspace)
            $_.Powershell.Dispose()
            $null = $JobsCompleted.Add($_)
          }
        }
      }
      $JobsCompleted | .{
        Process {
          $Jobs.Remove($_)
        }
      }
    }
    while ($Jobs)
  }
}

1..20 | Get-Example -ASync
