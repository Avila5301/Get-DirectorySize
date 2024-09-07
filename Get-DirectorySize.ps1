# Set the path to the folder you want to analyze
$folderPath = "C:\"

# Variables to control sorting and searching
$searchBy = "folder"  # Set to "folder" to search by folder or "file" to search by files
$sortBySize = $true   # Set to $true to sort by size
$sortByDate = $false  # Set to $true to sort by date modified
$omitFolders = @("C:\Windows", "C:\Program Files", "C:\Program Files (x86)", "C:\Users\Default", "C:\System Volume Information")

# Set the maximum number of concurrent jobs (adjust as needed)
$maxConcurrentJobs = 4 

# Function to check if a folder is omitted
function Check-OmittedFolder {
    param ($folder)
    return $omitFolders -contains $folder.FullName
}

# Function to check if a folder has subfolders
function Test-SubfolderExistence {
    param ($folder)
    return (Get-ChildItem -Path $folder.FullName -Directory -ErrorAction SilentlyContinue).Count -gt 0
}

# Function to calculate folder size
function Get-FolderSize {
    param ($folder)
    
    $folderSize = (Get-ChildItem -Path $folder.FullName -Recurse -Force -ErrorAction SilentlyContinue | 
                   Measure-Object -Property Length -Sum).Sum
    $lastModified = (Get-ChildItem -Path $folder.FullName -Recurse -Force -ErrorAction SilentlyContinue | 
                     Sort-Object LastWriteTime -Descending | 
                     Select-Object -First 1).LastWriteTime
                     
    [PSCustomObject]@{
        FolderName = $folder.FullName
        RootFolder = (Split-Path $folder.FullName -Parent)
        SizeInBytes = $folderSize
        Size = if ($folderSize -gt 1GB) { '{0:N2} GB' -f ($folderSize / 1GB) } else { '{0:N2} MB' -f ($folderSize / 1MB) }
        DateModified = $lastModified
    }
}

# Function to manage job execution with throttling
function Start-ThrottledJob {
    param ($jobScript, $argList)
    
    # Throttle the number of jobs
    while ((Get-Job -State Running).Count -ge $maxConcurrentJobs) {
        Start-Sleep -Seconds 1
    }
    
    # Start the job
    Start-Job -ScriptBlock $jobScript -ArgumentList $argList -InitializationScript {
        function Get-FolderSize {
            param ($folder)
            
            $folderSize = (Get-ChildItem -Path $folder.FullName -Recurse -Force -ErrorAction SilentlyContinue | 
                           Measure-Object -Property Length -Sum).Sum
            $lastModified = (Get-ChildItem -Path $folder.FullName -Recurse -Force -ErrorAction SilentlyContinue | 
                             Sort-Object LastWriteTime -Descending | 
                             Select-Object -First 1).LastWriteTime
                             
            [PSCustomObject]@{
                FolderName = $folder.FullName
                RootFolder = (Split-Path $folder.FullName -Parent)
                SizeInBytes = $folderSize
                Size = if ($folderSize -gt 1GB) { '{0:N2} GB' -f ($folderSize / 1GB) } else { '{0:N2} MB' -f ($folderSize / 1MB) }
                DateModified = $lastModified
            }
        }
    }
}

# Function to process folders with throttling
function Process-Folders {
    param ($folderPath)
    
    $folders = Get-ChildItem -Path $folderPath -Directory -Depth 1 -ErrorAction SilentlyContinue | 
               Where-Object { -not (Check-OmittedFolder $_) -and (Test-SubfolderExistence $_) -and ($_.FullName -notmatch '^C:\\[^\\]+$') }
               
    $jobs = @()
    
    foreach ($folder in $folders) {
        $jobs += Start-ThrottledJob -jobScript {
            param ($folder)
            Get-FolderSize -folder $folder
        } -argList $folder
    }
    
    $results = $jobs | Wait-Job | ForEach-Object { 
        Receive-Job -Job $_
        Remove-Job -Job $_
    }
    
    return $results
}

# Main logic
$startTimestamp = Get-Date
Write-Output "Script started at: $startTimestamp"

# Check if searchBy is set to 'file' and folderPath is set to C:\
if ($searchBy -eq 'file' -and $folderPath -eq 'C:\') {
    # Only search for files in the root directory, not subdirectories
    $fileSizes = Get-ChildItem -Path $folderPath -File -ErrorAction SilentlyContinue |
                 Where-Object { -not (Check-OmittedFolder $_) }
    
    if ($fileSizes.Count -gt 0) {
        $fileSizes = $fileSizes | Sort-Object Length -Descending | Select-Object -First 20
        
        Write-Output "Top 20 largest files in the root of C:\:"
        $fileSizes | Format-Table FullName, @{Name="Size";Expression={if ($_.Length -gt 1GB) { "{0:N2} GB" -f ($_.Length / 1GB) } else { "{0:N2} MB" -f ($_.Length / 1MB) }}}, LastWriteTime -AutoSize
    } else {
        Write-Output "No files found in the root of C:\."
    }
} else {
    if ($searchBy -eq 'folder') {
        $folderSizes = Process-Folders -folderPath $folderPath
        
        if ($sortBySize) {
            $folderSizes = $folderSizes | Sort-Object SizeInBytes -Descending
        } elseif ($sortByDate) {
            $folderSizes = $folderSizes | Sort-Object DateModified -Descending
        }
        
        $folderSizes = $folderSizes | Select-Object -First 20
        $top3LargestFolders = $folderSizes | Sort-Object RootFolder -Unique | Select-Object -First 3

        Write-Output "Top 20 largest directories:"
        $folderSizes | Format-Table FolderName, Size, DateModified -AutoSize
        
        # Search for top 5 largest files in each of the top 3 largest directories
        $fileSizes = @()
        foreach ($folder in $top3LargestFolders) {
            $fileSizes += Get-ChildItem -Path $folder.FolderName -File -Recurse -ErrorAction SilentlyContinue |
                          Where-Object { -not (Check-OmittedFolder $_) } |
                          Sort-Object Length -Descending |
                          Select-Object -First 5
        }
        
        $fileSizes = $fileSizes | Sort-Object Length -Descending
        
        Write-Output "Top 5 largest files within the top 3 largest directories:"
        $fileSizes | Format-Table FullName, @{Name="Size";Expression={if ($_.Length -gt 1GB) { "{0:N2} GB" -f ($_.Length / 1GB) } else { "{0:N2} MB" -f ($_.Length / 1MB) }}}, LastWriteTime -AutoSize
    } elseif ($searchBy -eq 'file') {
        $fileSizes = Get-ChildItem -Path $folderPath -File -Recurse -ErrorAction SilentlyContinue |
                     Where-Object { -not (Check-OmittedFolder $_) } |
                     Sort-Object Length -Descending |
                     Select-Object -First 20
        
        Write-Output "Top 20 largest files:"
        $fileSizes | Format-Table FullName, @{Name="Size";Expression={if ($_.Length -gt 1GB) { "{0:N2} GB" -f ($_.Length / 1GB) } else { "{0:N2} MB" -f ($_.Length / 1MB) }}}, LastWriteTime -AutoSize
    }
}

$endTimestamp = Get-Date
Write-Output "Script completed at: $endTimestamp"
