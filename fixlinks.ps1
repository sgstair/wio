
write-host "Starting..."

$curdir = (pwd).Path;
$mdfiles = gci -recurse | where {$_.Name -like "*.md"} | foreach {$_.fullname}
$otherfiles = gci -recurse | where {$_.Name -notlike "*.md"} | foreach {$_.fullname}

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

foreach($file in $otherfiles)
{
    # Track that file exists, so url will be updated when necessary
    $relpath = $file.replace($curdir,"").replace("\","/");
    $filemap[$relpath] = $true;
}

$redirectfrom = @{}; # Track URL rewrites so we can apply correct redirect_from tags

$regex = new-object Text.RegularExpressions.Regex "(\[[^\]]+\]\([^\)]+\))"
$changecount = 0;
$changefiles = 0;
$addedredirects = 0;
$errors = 0;
$errorfiles = @();

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
        
        $rewriteto = $url;
        
        # First case, if link is pointing to a .md, update it to .html
        $rewriteto = $rewriteto -replace "\.md$", ".html";
        
        # Second case, if url starts with /irchelp, rewrite it to 
        if($rewriteto.StartsWith("/irchelp/"))
        {
            if($filemap[$rewriteto] -ne $true)
            {
                # This link is broken, rewrite it to not include the irchelp prefix, if that will fix it
                $candidate = $rewriteto.substring("/irchelp".Length);
                if($filemap[$candidate])
                {
                    $redirectfrom[$candidate] = $rewriteto;
                    $rewriteto = $candidate;
                }
            }
        }
        
        # If the URL changed with above rules, rewrite it.
        if($rewriteto -ne $url)
        {
            $newtext = "$linkpart($candidate)";
            $alltext = $alltext.Replace($text,$newtext);
        
            if($changes -eq $false) { write-host "Updating $file" }
            $changes = $true;
            $changecount++;
            write-host "Changed URL '$url' to '$candidate'";
        
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

# Attempt to add missing redirect_from markers

foreach($file in $mdfiles)
{
    $relpath = $file.replace($curdir,"").replace("\","/");
    $relpath = $relpath -replace "\.md$",".html";
    
    if($redirectfrom[$relpath] -eq $null) { continue; } # This file does not need a redirect_from, don't examine.
        
    $alllines = [io.file]::ReadAllLines($file);
    
    write-host "Checking Redirects for $file";
    
    # Determine existing redirect_from elements
    $index = $alllines.indexof("redirect_from:");
    $redirects = @();
    if($index -ne -1)
    {
        while($true)
        {
            $index++;
            $line = $alllines[$index];
            if($line -match "^ \s+- (.*)$")
            {
                $redirects += $matches[1];
            }
            else
            {
                break;
            }
        }
    }    
    if($redirects.count -gt 0)
    {
        write-host ("Existing redirects: " + ($redirects -join ", "));
    }
    $need_new_redirect = $true;
    $from = $redirectfrom[$relpath];
    foreach($redir in $redirects)
    {
        if($redir -eq $from) { $need_new_redirect = $false; break; }
    }
    
    if(!$need_new_redirect)
    {
        write-host "Redirect already in place."
        continue;
    }
    
    # Add new redirect
    
    $newline = "  - $from";
    
    $index = $alllines.indexof("redirect_from:");
    if($index -eq -1)
    {
        write-host "No redirect_from tag present.";
        # Find the framing --- elements and insert a tag at the end.
        $index1 = $alllines.indexof("---");
        $index2 = [array]::IndexOf($alllines,"---",$index1+1);
        if($index2 -eq -1 -or $index1 -ne 0)
        {
            write-host "Could not find header to insert changes into.";
            $errors++;
            $errorfiles += $file;
            continue;
        }
        
        $alllines[$index2] = "redirect_from:`n$newline`n---";
    }
    else
    {
        # Tack on url to the redirect_from tag
        $alllines[$index] += "`n$newline";
    }
    write-host "Added redirect from $from";
    # Write file out
    $changefiles++;
    $addedredirects++;
    [io.file]::WriteAllLines($file, $alllines);
}

write-host "";
write-host "Done. Wrote $changefiles files ($errors errors, $changecount URL changes, $addedredirects redirects added)";
if($errorfiles.count -gt 0)
{
    write-host "";
    write-host "Redirect could not be added to the following files:";
    foreach($f in $errorfiles)
    {
        $relpath = $f.replace($curdir,"").replace("\","/");
        $from = $relpath -replace "\.md$",".html";
        $from = $redirectfrom[$from];
        write-host "$relpath (redirect_from: $from)";
    }
}


    