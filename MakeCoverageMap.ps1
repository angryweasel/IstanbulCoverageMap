#
# Powershell script to read coverage data from the Istanbul output, and then use
# a map file to map the source directory to an owning team.
#
# The coverage information, along with owning team are written to a CSV for slicing
# and dicing
#
# May have to eventually map per file, but this should work for now
#

#
# NOTE: If this script is moved, the relative paths in the next two lines will need to be updated
#

param([string]$coveragePath = $pwd.Path + "\..\build\tools\coverage")
$outputCSV = $coveragePath + "\CoverageMap.csv"
$csvMap = Import-Csv ".\filemap.csv" -Header Name,Team

#
# Do some sanity checking to make sure the script doesn't spew red text everywhere
#
if((Test-Path $coveragePath) -eq 0)
{
    Write-Warning "No coverage files exist in $coveragePath."
    Break
}

#
# Kill the existing csv if it exists
#
if ((Test-Path $outputCSV) -ne 0)
{
    Remove-Item $outputCSV
}


function Get-Owner ($name)
{
    if ((Test-Path ".\filemap.csv") -eq 0)
    {
        Write-Warning "filemap.csv doesn't exist in the current directory."
        Break
    }
    
    $lookup = $csvMap | where {$_.Name -eq $name}
    return $lookup.Team
}

function Get-LinesHit ($lines)
{
    [int] $count = 0
    foreach ($hitLines in $lines)
    {
        # NOTE: coverage output file counts number of times the line was hit
        #       we just want to know if it was hit or not
        if ($hitLines -ne 0)
        {
            $count += 1
        }
    }
    return $count
}


[xml]$covxml = Get-Content ($coveragePath + "\coverage.xml")
$xmlcontent = $covxml | Select-Xml -xpath "//package" | Select-Object -ExpandProperty "node"
$dirty = $false

foreach ($node in $xmlcontent)
{
    # normalize the path a bit for readability (map file matches this format too)
    if ($node.name.StartsWith("..build.src.") -eq $True)
    {
        $dirname = $node.name.Replace("..build.src.", "")
    }
    if ($node.name.StartsWith("src.") -eq $True)
    {
        $dirname = $node.name.Replace("src.", "")
    }
    #root node is blank
    if ($dirname -eq $null)
    {
        Continue
    }
    $owner = Get-Owner $dirname
    if ($owner -eq $null)
    {
        [double]$covRate = $node.'line-rate'
        Write-Warning "No team owner for $dirname ($('{0:P2}' -f $covRate)). Updating filemap.csv"
        Add-Content -path .\Filemap.csv "$dirname,Unknown"
        $dirty = $true
    }
    $lines = $node.ChildNodes.class.lines.line.Count
    $linesHit = Get-LinesHit $node.ChildNodes.class.lines.line.hits
    
    $outputLine =  $dirname + "," + $node.'line-rate' + "," + $lines + "," + $linesHit + "," + $owner
    Add-Content -path $outputCSV $outputLine
}

Write-Host "Coverage data correctly mapped to owners in $outputCSV"

#let's sort the csv file
if ($dirty -eq $true)
{
    $tempContent = Get-Content ".\filemap.csv" 
    $sortedContent = $tempContent | Sort-Object 
    $sortedContent | Set-Content ".\filemap.csv" 
    Write-Host "Filemap.csv updated. Please confirm changes (update 'unknowns' as applicable, and merge to develop"
}