#!/bin/bash
# Hasty script to convert a given standard Hugo post (where the post content and 
# images are stored separately) to a Page Bundle (where the content and images are
# stored together in the same directory). It does this by creating a new directory with 
# the same name as the designated post, moving the post into the new directory and 
# renaming it to "index.md", parsing the post to find all the image embeds in the format
# of "![Image description](/images/path/to/image.png)", moving the image files from
# their current location to the new Page Bundle directory, updating the image embed
# links within the post, and flipping the "usePageBundles" Front Matter parameter to
# "true" to enable the feature. It also does the same for thumbnails in YAML-formatted
# Front Matter, though not for featureImages or shareImages (simply becuase I don't have
# those defined in the posts I wanted to convert).
#
# Usage: ./convert-to-pagebundle.sh vpotato/content/posts/hello-hugo.md

inputPost="$1"                              # vpotato/content/posts/hello-hugo.md
postPath=$(dirname $inputPost)              # vpotato/content/posts
postTitle=$(basename $inputPost .md)        # hello-hugo
newPath="$postPath/$postTitle"              # vpotato/content/posts/hello-hugo
newPost="$newPath/index.md"                 # vpotato/content/posts/hello-hugo/index.md

siteBase=$(echo "$inputPost" | awk -F/ '{ print $1 }')  # vpotato
mkdir -p "$newPath"                         # make 'hello-hugo' dir
mv "$inputPost" "$newPost"                  # move 'hello-hugo.md' to 'hello-hugo/index.md'

imageLinks=($(grep -o -P '(?<=!\[)(?:[^\]]+)\]\(([^\)]+)' $newPost | grep -o -P '/images.*'))
# Ex: '/images/posts/image-name.png'
imageFiles=($(for file in ${imageLinks[@]}; do basename $file; done))
# Ex: 'image-name.png'
imagePaths=($(for file in ${imageLinks[@]}; do echo "$siteBase/static$file"; done))
# Ex: 'vpotato/static/images/posts/image-name.png'
for index in ${!imagePaths[@]}; do
    mv ${imagePaths[index]} $newPath
    # vpotato/static/images/posts/image-name.png --> vpotato/content/posts/hello-hugo/image-name.png
    sed -i "s^${imageLinks[index]}^${imageFiles[index]}^" $newPost
done

thumbnailLink=$(grep -P '^thumbnail:' $newPost | grep -o -P 'images.*')
# images/posts/thumbnail-name.png
if [[ $thumbnailLink ]]; then
    thumbnailFile=$(basename $thumbnailLink)    # thumbnail-name.png
    sed -i "s|thumbnail: $thumbnailLink|thumbnail: $thumbnailFile|" $newPost
    # relocate the thumbnail file if it hasn't already been moved
    if [[ ! -f "$newPath/$thumbnailFile" ]]; then
        mv "$siteBase/static/$thumbnailLink" "$newPath"
    done
fi
# enable page bundles
sed -i "s|usePageBundles: false|usePageBundles: true|" $newPost