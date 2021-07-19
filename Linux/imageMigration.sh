#!/bin/bash
# Hasty script to process a blog post markdown file, capture the URL for embedded images,
# download the image locally, and modify the markdown file with the relative image path.
#
# Run it from the top level of a Jekyll blog directory for best results, and pass the 
# filename of the blog post you'd like to process.
#
# Ex: ./imageMigration.sh 2021-07-19-Bulk-migrating-images-in-a-blog-post.md

postfile="_posts/$1"

imageUrls=($(grep -o -P '(?<=!\[)(?:[^\]]+)\]\(([^\)]+)' $postfile | grep -o -P 'http.*'))
imageNames=($(for name in ${imageUrls[@]}; do echo $name | grep -o -P '[^\/]+\.[[:alnum:]]+$'; done))
imagePaths=($(for name in ${imageNames[@]}; do echo "assets/images/posts/${name}"; done))
echo -e "\nProcessing $postfile...\n"
for index in ${!imageUrls[@]}; do
    echo -e "${imageUrls[index]}\n => ${imagePaths[index]}"
    curl ${imageUrls[index]} --output ${imagePaths[index]}
    sed -i "s|${imageUrls[index]}|${imagePaths[index]}|" $postfile
done

