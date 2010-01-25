#!/bin/sh

# SGF-Tools Spotlight Importer postinstall.sh

echo using find and xargs to tell mdimport to reindex all SGF files
su ${USER} -c "find / -iname *.sgf -print0 2>/dev/null | xargs -0 mdimport &"

# We were using the following Apple-recommended command, however it doesn't
# work properly the first time SGF-Tools is installed on a machine. :/
# su ${USER} -c "/usr/bin/mdimport -r '/Library/Spotlight/SGF.mdimporter'"
