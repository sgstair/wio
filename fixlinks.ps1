
$curdir = (pwd).Path;
$mdfiles = gci -recurse | where {$_.Name -like "*.md"} | foreach {$_.fullname}

$filemap = @{}
foreach($file in $mdfiles)
{
    $relpath = $file.replace($curdir,"").replace("\","/");
    # The files on the server are .html rather than .md
    $relpath = $relpath -replace "\.md$",".html";
    $filemap[$relpath] = $true;  
    
    if($relpath -like "*/index.html")
    {
        # Also track/fix links to directories that omit the index.html
        $relpath = $relpath.replace("/index.html","");
        $filemap[$relpath] = $true;  
    }
}

$regex = new-object Text.RegularExpressions.Regex "(\[[^\]]+\]\([^\)]+\))"
$changecount = 0;
$changefiles = 0;

foreach($file in $mdfiles)
{
    $alltext = [io.file]::ReadAllText($file);

    $allmatches = $regex.Matches($alltext);
    
    $changes = $false;

    foreach($match in $allmatches)
    {
        $text = [string]($match.Groups[0].Value);
        $splitpoint = $text.LastIndexOf("(");
        $url = $text.Substring($splitpoint+1, $text.Length-$splitpoint-2);
        $linkpart = $text.substring(0,$splitpoint);  
      
        if($url.StartsWith("/irchelp/"))
        {
            if($filemap[$url] -ne $true)
            {
                # This link is broken, rewrite it to not include the irchelp prefix, if that will fix it
                $candidate = $url.substring("/irchelp".Length);
                if($filemap[$candidate])
                {
                    $newtext = "$linkpart($candidate)";
                    $alltext = $alltext.Replace($text,$newtext);
                
                    if($changes -eq $false) { write-host "Updating $file" }
                    $changes = $true;
                    $changecount++;
                    write-host "Changed URL '$url' to '$candidate'";
                }
            }
        }
  

    }
    if($changes)
    {
        # Write modified file out.
        $changefiles++;
        [io.file]::WriteAllText($file, $alltext);
        write-host "Finished writing modified file."
    }      
}

write-host "";
write-host "Changed $changefiles files ($changecount total URL changes)"