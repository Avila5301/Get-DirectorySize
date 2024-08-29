# Set the path to the folder you want to analyze
$folderPath = "C:\" # Default is C:\ but you can change this to another drive or a specific path to search in

# Variables to control sorting and searching
$searchBy = "folder"  # Set to "folder" to search by folder or "file" to search by files | Default = Folder
$sortBySize = $true   # Set to $true to sort by size | Default = True
$sortByDate = $false  # Set to $true to sort by date modified | Default = False

# Array of folders to omit from the search
$omitFolders = @("C:\Windows", "C:\Program Files", "C:\Users\Default", "C:\System Volume Information")

# Function to check if a folder is in the omit list
function skipFolders($folder) {
    return $omitFolders -contains $folder.FullName
}

# Get the total number of directories or files for progress tracking
$totalItems = if ($searchBy -eq "folder") {
    (Get-ChildItem -Path $folderPath -Directory -Recurse -ErrorAction SilentlyContinue | Where-Object { -not (skipFolders $_) }).Count
} elseif ($searchBy -eq "file") {
    (Get-ChildItem -Path $folderPath -File -Recurse -ErrorAction SilentlyContinue | Where-Object { -not (skipFolders $_) }).Count
}
$counter = 0

if ($searchBy -eq "folder") {
    # Get all subdirectories, calculate their sizes, and capture the Date Modified
    $folderSizes = Get-ChildItem -Path $folderPath -Directory -Recurse -ErrorAction SilentlyContinue | Where-Object { -not (Is-OmittedFolder $_) } | ForEach-Object {
        $counter++
        Write-Progress -Activity "Processing Folders" -Status "$counter out of $totalItems" -PercentComplete (($counter / $totalItems) * 100)
        
        $folderSize = (Get-ChildItem -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        
        # Get the most recent modified date of the folder or its contents
        $lastModified = (Get-ChildItem -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime

        # Return a custom object with folder name, size in bytes, and date modified
        [PSCustomObject]@{
            FolderName = $_.FullName
            SizeInBytes = $folderSize
            Size = if ($folderSize -gt 1GB) {
                "{0:N2} GB" -f ($folderSize / 1GB)
            } else {
                "{0:N2} MB" -f ($folderSize / 1MB)
            }
            DateModified = $lastModified
        }
    }

    # Sort based on the specified criteria
    if ($sortBySize) {
        $folderSizes = $folderSizes | Sort-Object SizeInBytes -Descending
    } elseif ($sortByDate) {
        $folderSizes = $folderSizes | Sort-Object DateModified -Descending
    }

    # Limit results to top 20
    $folderSizes = $folderSizes | Select-Object -First 20

    # Display the results
    $folderSizes | Select-Object FolderName, Size, DateModified

} elseif ($searchBy -eq "file") {
    # Get all files, calculate their sizes, and capture the Date Modified
    $fileSizes = Get-ChildItem -Path $folderPath -File -Recurse -ErrorAction SilentlyContinue | Where-Object { -not (Is-OmittedFolder $_) } | ForEach-Object {
        $counter++
        Write-Progress -Activity "Processing Files" -Status "$counter out of $totalItems" -PercentComplete (($counter / $totalItems) * 100)
        
        # Return a custom object with file name, size in bytes, and date modified
        [PSCustomObject]@{
            FileName = $_.FullName
            SizeInBytes = $_.Length
            Size = if ($_.Length -gt 1GB) {
                "{0:N2} GB" -f ($_.Length / 1GB)
            } else {
                "{0:N2} MB" -f ($_.Length / 1MB)
            }
            DateModified = $_.LastWriteTime
        }
    }

    # Sort based on the specified criteria and select top 20 largest files
    if ($sortBySize) {
        $fileSizes = $fileSizes | Sort-Object SizeInBytes -Descending | Select-Object -First 20
    } elseif ($sortByDate) {
        $fileSizes = $fileSizes | Sort-Object DateModified -Descending | Select-Object -First 20
    }

    # Display the results
    $fileSizes | Select-Object FileName, Size, DateModified
}