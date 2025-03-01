#!/bin/bash
set -e
scriptdir="$(dirname $(readlink -f $0))"
outputdir="$3"
test -n "$outputdir" && test -d "$outputdir" || { echo "usage: $0 https://https://gitlab.jhuapl.edu/nationalhealth/essence/essence/-/wikis/home  user/project local-output-dir/ [_gitlab_session cookie hex value]"; exit 1; }
#cd "$outputdir" 
mkdir -p html/

### 0. FIXUP COMMANDLINE

# enforce trailing / in gitlab URL
gitlab_url="${1%/}/"
echo "using gitlab URL: $gitlab_url"

# remove trailing / in "user/repo":
repo="${2%/}"

### 1. DOWNLOAD HTML FILES
cd html
wget --rejected-log=rejected-urls.log --header "Cookie: _gitlab_session=$4" -r -k -p "$gitlab_url$repo/wikis/" -I "/$repo/uploads,/$repo/wikis,/assets" -R '*?version_id=*,?view=create,edit,history,git_access'
for i in */assets/*.css; do cat "$scriptdir"/remove-dynamic-content.css >> $i; done

# fixup lazy-loaded images (src="data:image-gif..." class="lazy" data-src="/user/project/uploads/.../source.png' for uploads,   or data-src="./source.png" for images inside wiki-git)
for depth in $(seq 1 100); do
    path_to_top=$(for i in $(seq 1 $(($depth-4))); do echo -n "../"; done)
    # TODO BUG: wikipages accidentaly named "something.txt" are excluded from this transformation (same for the copied regexp some lines below)
    find -maxdepth $depth -mindepth $depth -type f \( -name '*.html' -o -name '*.1' -o -not -regex ".*\.[a-zA-Z][a-zA-Z][a-zA-Z]?" \) -exec sed 's/src="data:image\/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw=="//g;s| data-src="'/$repo/'| src="'$path_to_top'|g;s| data-src="| src="|g' -i '{}' ';'
done

wikiindex="*/$repo/wikis/index.html"
wikiindex=$(echo $wikiindex)
xdg-open $wikiindex
ls $wikiindex

### 2. PDF GENERATION
### 2.1 PREPROCESS HTML
cat $scriptdir/redirect.html | sed 's|REPLACEME|'$wikiindex'|g' > index.html
cd ..
zip html.zip -r html/
cp -r html temp-for-pdf
cd temp-for-pdf

# work around a few bugs where gitlab doesn't enforce canonic URLs:
# force ending as .html, force filename as lowercase (except files already ending in .html), "-" is equal to " "
find */$repo/wikis/ -type f \( -name '*.1' -o -not -regex ".*\.[a-zA-Z][a-zA-Z][a-zA-Z]?" \) -not -name '*.html'  -execdir cp '{}'  '{}.copy.html' ';' -execdir rename -f 'y/A-Z\-/a-z /' '{}.copy.html' ';'

# deduplication: x.1 == x/index.html
for dir in $(find -mindepth 1 -type d); do
    dirname="$(basename $dir)"
    dirname="${dirname,,}" # convert to lowercase
    test -f $dir/index.html && rm -f $dir/../${dirname}.1.copy.html
done

# remove empty pages ("Create page XY" form)
find -name '*.html' -type f -exec sh -c 'fgrep -q "<form class=\"wiki-form common-note-form prepend-top-default js-quick-submit\" id=\"new_wiki_slug\"" "$1" && rm "$1"' dummy "{}" ";"


### 2.2 GENERATE PDF
find */$repo/wikis/ -name '*.html' -print -execdir chromium --headless --disable-gpu --print-to-pdf '{}' ';'  -execdir mv 'output.pdf' '{}.pdf' ';'
find -name '*.pdf' -exec pdfjoin --outfile all.pdf '{}' +
mv all.pdf ../
cd ..

xdg-open all.pdf
