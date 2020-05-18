#!/usr/bin/env bash
# Upload a file to Google Drive

usage() {
    printf "
The script can be used to upload file/directory to google drive.\n
Usage:\n %s [options.. ] <filename> <foldername>\n
Foldername argument is optional. If not provided, the file will be uploaded to preconfigured google drive.\n
File name argument is optional if create directory option is used.\n
Options:\n
  -C | --create-dir <foldername> - option to create directory. Will provide folder id. Can be used to provide input folder, see README.\n
  -r | --root-dir <google_folderid> or <google_folder_url> - google folder ID/URL to which the file/directory is going to upload.\nIf you want to change the default value, then use this format, -r/--root-dir default=root_folder_id/root_folder_url\n
  -s | --skip-subdirs - Skip creation of sub folders and upload all files inside the INPUT folder/sub-folders in the INPUT folder, use this along with -p/--parallel option to speed up the uploads.\n
  -p | --parallel <no_of_files_to_parallely_upload> - Upload multiple files in parallel, Max value = 10.\n
  -f | --[file|folder] - Specify files and folders explicitly in one command, use multiple times for multiple folder/files. See README for more use of this command.\n 
  -o | --overwrite - Overwrite the files with the same name, if present in the root folder/input folder, also works with recursive folders.\n
  -d | --skip-duplicates - Do not upload the files with the same name, if already present in the root folder/input folder, also works with recursive folders.\n
  -S | --share <optional_email_address>- Share the uploaded input file/folder, grant reader permission to provided email address or to everyone with the shareable link.\n
  -i | --save-info <file_to_save_info> - Save uploaded files info to the given filename.\n
  -z | --config <config_path> - Override default config file with custom config file.\nIf you want to change default value, then use this format -z/--config default=default=your_config_file_path.\n
  -q | --quiet - Supress the normal output, only show success/error upload messages for files, and one extra line at the beginning for folder showing no. of files and sub folders.\n
  -v | --verbose - Display detailed message (only for non-parallel uploads).\n
  -V | --verbose-progress - Display detailed message and detailed upload progress(only for non-parallel uploads).\n
  -u | --update - Update the installed script in your system.\n
  --info - Show detailed info, only if script is installed system wide.\n
  -U | --uninstall - Uninstall script, remove related files.\n
  -D | --debug - Display script command trace.\n
  -h | --help - Display usage instructions.\n" "${0##*/}"
    exit 0
}

shortHelp() {
    printf "No valid arguments provided, use -h/--help flag to see usage.\n"
    exit 0
}

# Exit if bash present on system is older than 4.x
checkBashVersion() {
    { ! [[ ${BASH_VERSINFO:-0} -ge 4 ]] && printf "Bash version lower than 4.x not supported.\n" && exit 1; } || :
}

# Check if we are running in a terminal.
isTerminal() {
    [[ -t 1 || -z ${TERM} ]] && return 0 || return 1
}

# Usage: bashSleep 1 ( where is time in seconds )
# https://github.com/dylanaraps/pure-bash-bible#use-read-as-an-alternative-to-the-sleep-command
bashSleep() {
    read -rt "${1}" <> <(:) || :
}

# Move cursor to nth no. of line and clear it to the begining.
# Usage: clearLine x ( where x is the no of line you wanna clear )
clearLine() {
    printf "\033[%sA\033[2K" "${1}"
}

# Convert bytes to human readable form, pure bash.
# Usage: bytesToHuman bytes
# https://unix.stackexchange.com/a/259254
bytesToHuman() {
    declare b=${1:-0} d='' s=0 S=(Bytes {K,M,G,T,P,E,Y,Z}B)
    while ((b > 1024)); do
        d="$(printf ".%02d" $((b % 1024 * 100 / 1024)))"
        b=$((b / 1024)) && ((s++))
    done
    printf "%s\n" "${b}${d} ${S[${s}]}"
}

# Default curl command for every curl request in this script, just to decrease script line :p
curlCmd() {
    curl --compressed "${@}"
}

# Usage: dirname "path" ( alternative to dirname command )
# https://github.com/dylanaraps/pure-bash-bible#get-the-directory-name-of-a-file-path
dirname() {
    declare tmp=${1:-.}

    [[ ${tmp} != *[!/]* ]] && { printf '/\n' && return; }
    tmp="${tmp%%"${tmp##*[!/]}"}"

    [[ ${tmp} != */* ]] && { printf '.\n' && return; }
    tmp=${tmp%/*} && tmp="${tmp%%"${tmp##*[!/]}"}"

    printf '%s\n' "${tmp:-/}"
}

# Update ( install, uninstall ) the script
update() {
    declare job="${1}"
    printf 'Fetching %s script..\n' "${job:-update}"
    # shellcheck source=/dev/null
    if [[ -f "${HOME}/.google-drive-upload/google-drive-upload.info" ]]; then
        source "${HOME}/.google-drive-upload/google-drive-upload.info"
    fi
    declare REPO="${REPO:-labbots/google-drive-upload}" TYPE_VALUE="${TYPE_VALUE:-latest}"
    if [[ ${TYPE} = branch ]]; then
        if __SCRIPT="$(curlCmd -Ls "https://raw.githubusercontent.com/${REPO}/${TYPE_VALUE}/install.sh")"; then
            bash <(printf "%s\n" "${__SCRIPT}") --"${job:-}"
        else
            printf "Error: Cannot download %s script..\n" "${job:-update}"
        fi
    else
        declare LATEST_SHA
        LATEST_SHA="$(curl --compressed -s https://api.github.com/repos/"${3:-${REPO}}"/releases/"${2:-${TYPE_VALUE}}" | jsonValue tag_name)"
        if __SCRIPT="$(curlCmd -Ls "https://raw.githubusercontent.com/${REPO}/${LATEST_SHA}/install.sh")"; then
            bash <(printf "%s\n" "${__SCRIPT}") --"${job:-}"
        else
            printf "Error: Cannot download %s script..\n" "${job:-update}"
        fi
    fi
}

# Just print the "${HOME}/.google-drive-upload/google-drive-upload.info"
versionInfo() {
    # shellcheck source=/dev/null
    if [[ -f "${HOME}/.google-drive-upload/google-drive-upload.info" ]]; then
        printf "%s\n" "$(< "${HOME}/.google-drive-upload/google-drive-upload.info")"
    else
        printf "google-drive-upload is not installed system wide.\n"
    fi
}

# Print a text to center interactively and fill the rest of the line with text specified.
# This function is fine-tuned to this script functionality, so may appear unusual.
# Usage: printCenter normal/justify sometext filler_symbol or sometext sometext2 filler_symbol
# https://gist.github.com/TrinityCoder/911059c83e5f7a351b785921cf7ecda
printCenter() {
    [[ $# -lt 3 ]] && printf "%s: Missing arguments\n" "${FUNCNAME[0]}" && return 1
    declare -i TERM_COLS="${COLUMNS}"
    declare type="${1}" filler
    case "${type}" in
        normal)
            declare out="${2}" && symbol="${3}"
            ;;
        justify)
            if [[ $# = 3 ]]; then
                declare input1="${2}" symbol="${3}" TO_PRINT out
                TO_PRINT="$((TERM_COLS * 95 / 100))"
                { [[ ${#input1} -gt ${TO_PRINT} ]] && out="[ ${input1:0:TO_PRINT}.. ]"; } || { out="[ ${input1} ]"; }
            else
                declare input1="${2}" input2="${3}" symbol="${4}" TO_PRINT temp out
                TO_PRINT="$((TERM_COLS * 40 / 100))"
                { [[ ${#input1} -gt ${TO_PRINT} ]] && temp+=" ${input1:0:TO_PRINT}.."; } || { temp+=" ${input1}"; }
                TO_PRINT="$((TERM_COLS * 55 / 100))"
                { [[ ${#input2} -gt ${TO_PRINT} ]] && temp+="${input2:0:TO_PRINT}.. "; } || { temp+="${input2} "; }
                out="[${temp}]"
            fi
            ;;
        *) return 1 ;;
    esac

    declare -i str_len=${#out}
    [[ $str_len -ge $(((TERM_COLS - 1))) ]] && {
        printf "%s\n" "${out}" && return 0
    }

    declare -i filler_len="$(((TERM_COLS - str_len) / 2))"
    [[ $# -ge 2 ]] && ch="${symbol:0:1}" || ch=" "
    for ((i = 0; i < filler_len; i++)); do
        filler="${filler}${ch}"
    done

    printf "%s%s%s" "${filler}" "${out}" "${filler}"
    [[ $(((TERM_COLS - str_len) % 2)) -ne 0 ]] && printf "%s" "${ch}"
    printf "\n"

    return 0
}

# Usage: count < "file" or count <<< "$variable" or pipe some output. ( alt to wc -l )
# https://github.com/dylanaraps/pure-bash-bible#get-the-number-of-lines-in-a-file
count() {
    mapfile -tn 0 lines
    printf '%s\n' "${#lines[@]}"
}

# Method to extract data from json response.
# Usage: jsonValue key < json ( or use with a pipe output ).
jsonValue() {
    [[ $# = 0 ]] && printf "%s: Missing arguments\n" "${FUNCNAME[0]}" && return 1
    declare LC_ALL=C num="${2:-1}"
    grep -o "\"""${1}""\"\:.*" | sed -e "s/.*\"""${1}""\": //" -e 's/[",]*$//' -e 's/["]*$//' -e 's/[,]*$//' -e "s/\"//" -n -e "${num}"p
}

# Remove array duplicates, maintain the order as original.
# Usage: removeArrayDuplicates "${somearray[@]}"
# https://stackoverflow.com/a/37962595
removeArrayDuplicates() {
    [[ $# = 0 ]] && printf "%s: Missing arguments\n" "${FUNCNAME[0]}" && return 1
    declare -A Aseen
    Aunique=()
    for i in "$@"; do
        { [[ -z ${i} || ${Aseen[${i}]} ]]; } && continue
        Aunique+=("${i}") && Aseen[${i}]=x
    done
    printf '%s\n' "${Aunique[@]}"
}

# Update Config. Incase of old value, update, for new value add.
# Usage: updateConfig valuename value configpath
updateConfig() {
    [[ $# -lt 3 ]] && printf "%s: Missing arguments\n" "${FUNCNAME[0]}" && return 1
    declare VALUE_NAME="${1}" VALUE="${2}" CONFIG_PATH="${3}" FINAL=()
    printf "" >> "${CONFIG_PATH}" # If config file doesn't exist.
    mapfile -t VALUES < "${CONFIG_PATH}" && VALUES+=("${VALUE_NAME}=\"${VALUE}\"")
    for i in "${VALUES[@]}"; do
        [[ ${i} =~ ${VALUE_NAME}\= ]] && FINAL+=("${VALUE_NAME}=\"${VALUE}\"") || FINAL+=("${i}")
    done
    removeArrayDuplicates "${FINAL[@]}" >| "${CONFIG_PATH}"
}

# Extract file/folder ID from the given INPUT in case of gdrive URL.
# Usage: extractID gdriveurl
extractID() {
    [[ $# = 0 ]] && printf "%s: Missing arguments\n" "${FUNCNAME[0]}" && return 1
    declare LC_ALL=C ID="${1//[[:space:]]/}"
    case "${ID}" in
        *'drive.google.com'*'id='*) ID="${ID/*id=/}" && ID="${ID/&*/}" && ID="${ID/\?*/}" ;;
        *'drive.google.com'*'file/d/'* | 'http'*'docs.google.com/file/d/'*) ID="${ID/*\/d\//}" && ID="${ID/\/*/}" ;;
        *'drive.google.com'*'drive'*'folders'*) ID="${ID/*\/folders\//}" && ID="${ID/&*/}" && ID="${ID/\?*/}" ;;
    esac
    printf "%s\n" "${ID}"
}

# Usage: urlEncode "string".
# https://github.com/dylanaraps/pure-bash-bible#percent-encode-a-string
urlEncode() {
    declare LC_ALL=C
    for ((i = 0; i < ${#1}; i++)); do
        : "${1:i:1}"
        case "${_}" in
            [a-zA-Z0-9.~_-])
                printf '%s' "${_}"
                ;;
            *)
                printf '%%%02X' "'${_}"
                ;;
        esac
    done
    printf '\n'
}

# Method to get information for a gdrive folder/file.
# Requirements: Given file/folder ID, query, and access_token.
driveInfo() {
    [[ $# -lt 3 ]] && printf "%s: Missing arguments\n" "${FUNCNAME[0]}" && return 1
    declare FOLDER_ID="${1}" FETCH="${2}" TOKEN="${3}"
    declare SEARCH_RESPONSE FETCHED_DATA

    SEARCH_RESPONSE="$(curlCmd -s \
        -H "Authorization: Bearer ${TOKEN}" \
        "${API_URL}/drive/${API_VERSION}/files/${FOLDER_ID}?fields=${FETCH}&supportsAllDrives=true")"

    FETCHED_DATA="$(jsonValue "${FETCH}" 1 <<< "${SEARCH_RESPONSE}")"
    { [[ -z ${FETCHED_DATA} ]] && jsonValue message 1 <<< "${SEARCH_RESPONSE}" && return 1; } || {
        printf "%s\n" "${FETCHED_DATA}"
    }
}

# Search for an existing file with write permission.
# Requirements: Given file name, rootdir, and access_token.
checkExistingFile() {
    [[ $# -lt 3 ]] && printf "%s: Missing arguments\n" "${FUNCNAME[0]}" && return 1
    declare NAME="${1}" ROOTDIR="${2}" TOKEN="${3}"
    declare QUERY SEARCH_RESPONSE ID

    QUERY="$(urlEncode "name='${NAME}' and '${ROOTDIR}' in parents and trashed=false and 'me' in writers")"

    SEARCH_RESPONSE="$(curlCmd -s \
        -H "Authorization: Bearer ${TOKEN}" \
        "${API_URL}/drive/${API_VERSION}/files?q=${QUERY}&fields=files(id)")"

    ID="$(jsonValue id 1 <<< "${SEARCH_RESPONSE}")"
    printf "%s\n" "${ID}"
}

# Method to create directory in google drive.
# Requirements: Foldername, Root folder ID ( the folder in which the new folder will be created ) and access_token.
createDirectory() {
    [[ $# -lt 3 ]] && printf "%s: Missing arguments\n" "${FUNCNAME[0]}" && return 1
    declare DIRNAME="${1}" ROOTDIR="${2}" TOKEN="${3}"
    declare QUERY SEARCH_RESPONSE FOLDER_ID

    QUERY="$(urlEncode "mimeType='application/vnd.google-apps.folder' and name='${DIRNAME}' and trashed=false and '${ROOTDIR}' in parents")"

    SEARCH_RESPONSE="$(curlCmd -s \
        -H "Authorization: Bearer ${TOKEN}" \
        "${API_URL}/drive/${API_VERSION}/files?q=${QUERY}&fields=files(id)&supportsAllDrives=true")"

    FOLDER_ID="$(printf "%s\n" "${SEARCH_RESPONSE}" | jsonValue id 1)"

    if [[ -z ${FOLDER_ID} ]]; then
        declare CREATE_FOLDER_POST_DATA CREATE_FOLDER_RESPONSE
        CREATE_FOLDER_POST_DATA="{\"mimeType\": \"application/vnd.google-apps.folder\",\"name\": \"${DIRNAME}\",\"parents\": [\"${ROOTDIR}\"]}"
        CREATE_FOLDER_RESPONSE="$(curlCmd -s \
            -X POST \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json; charset=UTF-8" \
            -d "${CREATE_FOLDER_POST_DATA}" \
            "${API_URL}/drive/${API_VERSION}/files?fields=id&supportsAllDrives=true")"
        FOLDER_ID="$(jsonValue id <<< "${CREATE_FOLDER_RESPONSE}")"
    fi
    printf "%s\n" "${FOLDER_ID}"
}

# Method to upload ( create or update ) files to google drive.
# Interrupted uploads can be resumed.
# Requirements: Given file path, Google folder ID and access_token.
uploadFile() {
    [[ $# -lt 4 ]] && printf "%s: Missing arguments\n" "${FUNCNAME[0]}" && return 1
    declare JOB="${1}" INPUT="${2}" FOLDER_ID="${3}" TOKEN="${4}" PARALLEL="${5}"
    declare SLUG INPUTNAME EXTENSION INPUTSIZE READABLE_SIZE REQUEST_METHOD URL POSTDATA UPLOADLINK UPLOAD_BODY STRING

    SLUG="${INPUT##*/}"
    INPUTNAME="${SLUG%.*}"
    EXTENSION="${SLUG##*.}"
    INPUTSIZE="$(wc -c < "${INPUT}")"
    READABLE_SIZE="$(bytesToHuman "${INPUTSIZE}")"

    # Handle extension-less files
    if [[ ${INPUTNAME} = "${EXTENSION}" ]]; then
        declare MIME_TYPE
        if type -p mimetype &> /dev/null; then
            MIME_TYPE="$(mimetype --output-format %m "${INPUT}")"
        elif type -p file &> /dev/null; then
            MIME_TYPE="$(file --brief --mime-type "${INPUT}")"
        else
            printCenter "justify" "Error: file or mimetype command not found." && printf "\n"
            exit 1
        fi
    fi

    # Set proper variables for overwriting files
    if [[ ${JOB} = update ]]; then
        declare EXISTING_FILE_ID
        # Check if file actually exists, and create if not.
        EXISTING_FILE_ID=$(checkExistingFile "${SLUG}" "${FOLDER_ID}" "${ACCESS_TOKEN}")
        if [[ -n ${EXISTING_FILE_ID} ]]; then
            if [[ -n ${SKIP_DUPLICATES} ]]; then
                SKIP_DUPLICATES_FILE_ID="${EXISTING_FILE_ID}"
                FILE_LINK="${SKIP_DUPLICATES_FILE_ID/${SKIP_DUPLICATES_FILE_ID}/https://drive.google.com/open?id=${SKIP_DUPLICATES_FILE_ID}}"
            else
                # https://developers.google.com/drive/api/""${API_VERSION}""/reference/files/update
                REQUEST_METHOD="PATCH"
                URL="${API_URL}/upload/drive/${API_VERSION}/files/${EXISTING_FILE_ID}?uploadType=resumable&supportsAllDrives=true&supportsTeamDrives=true"
                # JSON post data to specify the file name and folder under while the file to be updated
                POSTDATA="{\"mimeType\": \"${MIME_TYPE}\",\"name\": \"${SLUG}\",\"addParents\": [\"${FOLDER_ID}\"]}"
                STRING="Updated"
            fi
        else
            JOB="create"
        fi
    fi

    if [[ -n ${SKIP_DUPLICATES_FILE_ID} ]]; then
        # Stop upload if already exists ( -d/--skip-duplicates )
        "${QUIET:-printCenter}" "justify" "${SLUG}" " already exists." "="
    else
        # Set proper variables for creating files
        if [[ ${JOB} = create ]]; then
            URL="${API_URL}/upload/drive/${API_VERSION}/files?uploadType=resumable&supportsAllDrives=true&supportsTeamDrives=true"
            REQUEST_METHOD="POST"
            # JSON post data to specify the file name and folder under while the file to be created
            POSTDATA="{\"mimeType\": \"${MIME_TYPE}\",\"name\": \"${SLUG}\",\"parents\": [\"${FOLDER_ID}\"]}"
            STRING="Uploaded"
        fi

        [[ -z ${PARALLEL} ]] && printCenter "justify" "${INPUT##*/}" " | ${READABLE_SIZE}" "="

        generateUploadLink() {
            UPLOADLINK="$(curlCmd -s \
                -X "${REQUEST_METHOD}" \
                -H "Authorization: Bearer ${TOKEN}" \
                -H "Content-Type: application/json; charset=UTF-8" \
                -H "X-Upload-Content-Type: ${MIME_TYPE}" \
                -H "X-Upload-Content-Length: ${INPUTSIZE}" \
                -d "$POSTDATA" \
                "${URL}" \
                -D -)"
            UPLOADLINK="$(read -r firstline <<< "${UPLOADLINK/*[L,l]ocation: /}" && printf "%s\n" "${firstline//$'\r'/}")"
        }

        uploadFilefromURI() {
            # Curl command to push the file to google drive.
            [[ -z ${PARALLEL} ]] && clearLine 1 && printCenter "justify" "Uploading.." "-"
            # shellcheck disable=SC2086 # Because unnecessary to another check because ${CURL_ARGS} won't be anything problematic.
            UPLOAD_BODY="$(curlCmd \
                -X PUT \
                -H "Authorization: Bearer ${TOKEN}" \
                -H "Content-Type: ${MIME_TYPE}" \
                -H "Content-Length: ${INPUTSIZE}" \
                -H "Slug: ${SLUG}" \
                -T "${INPUT}" \
                -o- \
                --url "${UPLOADLINK}" \
                --globoff \
                ${CURL_ARGS})"
        }

        collectFileInfo() {
            FILE_LINK="$(: "$(printf "%s\n" "${UPLOAD_BODY}" | jsonValue id)" && printf "%s\n" "${_/$_/https://drive.google.com/open?id=$_}")"
            FILE_ID="$(printf "%s\n" "${UPLOAD_BODY}" | jsonValue id)"
            # Log to the filename provided with -i/--save-id flag.
            if [[ -n ${LOG_FILE_ID} && ! -d ${LOG_FILE_ID} ]]; then
                # shellcheck disable=SC2129
                # https://github.com/koalaman/shellcheck/issues/1202#issuecomment-608239163
                {
                    printf "%s\n" "Link: ${FILE_LINK}"
                    : "$(printf "%s\n" "${UPLOAD_BODY}" | jsonValue name)" && printf "%s\n" "${_/*/Name: $_}"
                    : "$(printf "%s\n" "${UPLOAD_BODY}" | jsonValue id)" && printf "%s\n" "${_/*/ID: $_}"
                    : "$(printf "%s\n" "${UPLOAD_BODY}" | jsonValue mimeType)" && printf "%s\n" "${_/*/Type: $_}"
                    printf '\n'
                } >> "${LOG_FILE_ID}"
            fi
        }

        normalLogging() {
            if [[ -z ${VERBOSE_PROGRESS:-${PARALLEL}} ]]; then
                for _ in {1..3}; do clearLine 1; done
            fi
            "${QUIET:-printCenter}" "justify" "${SLUG} " "| ${READABLE_SIZE} | ${STRING}" "="
        }

        errorLogging() {
            "${QUIET:-printCenter}" "justify" "Upload link generation ERROR" ", ${SLUG} not ${STRING}." "=" 1>&2 && [[ -z ${PARALLEL} ]] && printf "\n\n\n" 1>&2
            UPLOAD_STATUS="ERROR" && export UPLOAD_STATUS # Send a error status, used in folder uploads.
        }

        # Used for resuming interrupted uploads
        logUploadSession() {
            { [[ ${INPUTSIZE} -gt 1000000 ]] && printf "%s\n" "${UPLOADLINK}" >| "${__file}"; } || :
        }

        removeUploadSession() {
            rm -f "${__file}"
        }

        fullUpload() {
            generateUploadLink
            if [[ -n ${UPLOADLINK} ]]; then
                logUploadSession
                uploadFilefromURI
                if [[ -n ${UPLOAD_BODY} ]]; then
                    collectFileInfo
                    normalLogging
                    removeUploadSession
                else
                    errorLogging
                fi
            else
                errorLogging
            fi
        }

        __file="${HOME}/.google-drive-upload/${SLUG}__::__${FOLDER_ID}__::__${INPUTSIZE}"
        # https://developers.google.com/drive/api/v3/manage-uploads
        if [[ -r "${__file}" ]]; then
            UPLOADLINK="$(< "${__file}")"
            HTTP_CODE="$(curlCmd -s -X PUT "${UPLOADLINK}" --write-out %"{http_code}")"
            if [[ ${HTTP_CODE} = "308" ]]; then # Active Resumable URI give 308 status
                UPLOADED_RANGE="$(: "$(curlCmd -s \
                    -X PUT \
                    -H "Content-Range: bytes */${INPUTSIZE}" \
                    --url "${UPLOADLINK}" \
                    --globoff \
                    -D -)" && : "$(printf "%s\n" "${_/*[R,r]ange: bytes=0-/}")" && read -r firstline <<< "$_" && printf "%s\n" "${firstline//$'\r'/}")"
                if [[ ${UPLOADED_RANGE} =~ (^[0-9]) ]]; then
                    CONTENT_RANGE="$(printf "bytes %s-%s/%s\n" "$((UPLOADED_RANGE + 1))" "$((INPUTSIZE - 1))" "${INPUTSIZE}")"
                    CONTENT_LENGTH="$((INPUTSIZE - $((UPLOADED_RANGE + 1))))"
                    [[ -z ${PARALLEL} ]] && {
                        printCenter "justify" "Resuming interrupted upload.." "-"
                        printCenter "justify" "Uploading.." "-"
                    }
                    # shellcheck disable=SC2086 # Because unnecessary to another check because ${CURL_ARGS} won't be anything problematic.
                    # Resuming interrupted uploads needs http1.1
                    UPLOAD_BODY="$(curlCmd -s \
                        --http1.1 \
                        -X PUT \
                        -H "Authorization: Bearer ${TOKEN}" \
                        -H "Content-Type: ${MIME_TYPE}" \
                        -H "Content-Range: ${CONTENT_RANGE}" \
                        -H "Content-Length: ${CONTENT_LENGTH}" \
                        -H "Slug: ${SLUG}" \
                        -T "${INPUT}" \
                        -o- \
                        --url "${UPLOADLINK}" \
                        --globoff)" || :
                    if [[ -n ${UPLOAD_BODY} ]]; then
                        collectFileInfo
                        normalLogging resume
                        removeUploadSession
                    else
                        errorLogging
                    fi
                else
                    [[ -z ${PARALLEL} ]] && printCenter "justify" "Generating upload link.." "-"
                    fullUpload
                fi
            elif [[ ${HTTP_CODE} =~ 40* ]]; then # Dead Resumable URI give 400,404.. status
                [[ -z ${PARALLEL} ]] && printCenter "justify" "Generating upload link.." "-"
                fullUpload
            elif [[ ${HTTP_CODE} =~ [200,201] ]]; then # Completed Resumable URI give 200 or 201 status
                UPLOAD_BODY="${HTTP_CODE}"
                collectFileInfo
                normalLogging
                removeUploadSession
            fi
        else
            [[ -z ${PARALLEL} ]] && printCenter "justify" "Generating upload link.." "-"
            fullUpload
        fi
    fi
}

# Method to share a gdrive file/folder
# Requirements: Given file/folder ID, type, role and access_token.
shareID() {
    [[ $# -lt 2 ]] && printf "%s: Missing arguments\n" "${FUNCNAME[0]}" && return 1
    declare LC_ALL=C ID="${1}" TOKEN="${2}" SHARE_EMAIL="${3}" ROLE="reader" TYPE="anyone"
    declare TYPE SHARE_POST_DATA SHARE_POST_DATA SHARE_RESPONSE SHARE_ID

    if [[ -n ${SHARE_EMAIL} ]]; then
        TYPE="user"
        SHARE_POST_DATA="{\"role\":\"${ROLE}\",\"type\":\"${TYPE}\",\"emailAddress\":\"${SHARE_EMAIL}\"}"
    else
        SHARE_POST_DATA="{\"role\":\"${ROLE}\",\"type\":\"${TYPE}\"}"
    fi
    SHARE_RESPONSE="$(curlCmd -s \
        -X POST \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json; charset=UTF-8" \
        -d "${SHARE_POST_DATA}" \
        "${API_URL}/drive/${API_VERSION}/files/${ID}/permissions")"

    SHARE_ID="$(jsonValue id 1 <<< "${SHARE_RESPONSE}")"
    [[ -z "${SHARE_ID}" ]] && jsonValue message 1 <<< "${SHARE_RESPONSE}" && return 1
}

# Setup the varibles and process getopts flags.
setupArguments() {
    [[ $# = 0 ]] && printf "%s: Missing arguments\n" "${FUNCNAME[0]}" && return 1
    # Internal variables
    # De-initialize if any variables set already.
    unset FIRST_INPUT FOLDER_INPUT FOLDERNAME FINAL_INPUT_ARRAY INPUT_ARRAY
    unset PARALLEL NO_OF_PARALLEL_JOBS SHARE SHARE_EMAIL OVERWRITE SKIP_DUPLICATES SKIP_SUBDIRS ROOTDIR QUIET
    unset VERBOSE VERBOSE_PROGRESS DEBUG LOG_FILE_ID
    CURL_ARGS="-#"
    INFO_PATH="${HOME}/.google-drive-upload"
    CONFIG="$(< "${INFO_PATH}/google-drive-upload.configpath")" &> /dev/null || :

    # Grab the first and second argument and shift, only if ${1} doesn't contain -.
    { ! [[ ${1} = -* ]] && INPUT_ARRAY+=("${1}") && shift && [[ ${1} != -* ]] && FOLDER_INPUT="${1}" && shift; } || :

    # Configuration variables # Remote gDrive variables
    unset ROOT_FOLDER CLIENT_ID CLIENT_SECRET REFRESH_TOKEN ACCESS_TOKEN
    API_URL="https://www.googleapis.com"
    API_VERSION="v3"
    SCOPE="${API_URL}/auth/drive"
    REDIRECT_URI="urn:ietf:wg:oauth:2.0:oob"
    TOKEN_URL="https://accounts.google.com/o/oauth2/token"

    SHORTOPTS=":qvVi:sp:odf:ShuUr:C:Dz:-:"
    while getopts "${SHORTOPTS}" OPTION; do
        checkDefault() {
            eval "${2}" "$([[ ${2} = default* ]] && printf "%s\n" "${3}")"
        }
        checkConfig() {
            if [[ -r ${1} ]]; then
                CONFIG="${1}" && UPDATE_DEFAULT_CONFIG="true"
            else
                printf "Error: Given config file (%s) doesn't exist/not readable,..\n" "${1}" 1>&2 && exit 1
            fi
        }
        case "${OPTION}" in
            # Parse longoptions # https://stackoverflow.com/questions/402377/using-getopts-to-process-long-and-short-command-line-options/28466267#28466267
            -)
                checkLongoptions() { { [[ -n ${!OPTIND} ]] &&
                    printf '%s: --%s: option requires an argument\nTry '"%s -h/--help"' for more information.\n' "${0##*/}" "${OPTARG}" "${0##*/}" && exit 1; } || :; }
                case "${OPTARG}" in
                    help)
                        usage
                        ;;
                    update)
                        update && exit $?
                        ;;
                    uninstall)
                        update uninstall && exit $?
                        ;;
                    info)
                        versionInfo && exit $?
                        ;;
                    create-dir)
                        checkLongoptions
                        FOLDERNAME="${!OPTIND}" && OPTIND=$((OPTIND + 1))
                        ;;
                    root-dir)
                        checkLongoptions
                        checkDefault "${!OPTIND}" "ROOTDIR=${!OPTIND/default=/}" "UPDATE_DEFAULT_ROOTDIR=updateConfig"
                        OPTIND=$((OPTIND + 1))

                        ;;
                    config)
                        checkLongoptions
                        checkDefault "${!OPTIND}" "checkConfig" "${!OPTIND/default=/}"
                        OPTIND=$((OPTIND + 1))
                        ;;
                    save-info)
                        checkLongoptions
                        LOG_FILE_ID="${!OPTIND}" && OPTIND=$((OPTIND + 1))
                        ;;
                    skip-subdirs)
                        SKIP_SUBDIRS="true"
                        ;;
                    parallel)
                        checkLongoptions
                        NO_OF_PARALLEL_JOBS="${!OPTIND}"
                        case "${NO_OF_PARALLEL_JOBS}" in
                            '' | *[!0-9]*)
                                printf "\nError: -p/--parallel value ranges between 1 to 10.\n"
                                exit 1
                                ;;
                            *)
                                [[ ${NO_OF_PARALLEL_JOBS} -gt 10 ]] && { NO_OF_PARALLEL_JOBS=10 || NO_OF_PARALLEL_JOBS="${!OPTIND}"; }
                                ;;
                        esac
                        PARALLEL_UPLOAD="true" && OPTIND=$((OPTIND + 1))
                        ;;
                    overwrite)
                        OVERWRITE="Overwrite" && UPLOAD_METHOD="update"
                        ;;
                    skip-duplicates)
                        SKIP_DUPLICATES="true" && UPLOAD_METHOD="update"
                        ;;
                    file | folder)
                        checkLongoptions
                        INPUT_ARRAY+=("${!OPTIND}") && OPTIND=$((OPTIND + 1))
                        ;;
                    share)
                        SHARE="true"
                        # https://stackoverflow.com/a/57295993
                        # Optional arguments # https://stackoverflow.com/questions/402377/using-getopts-to-process-long-and-short-command-line-options/28466267#28466267
                        EMAIL_REGEX="^([A-Za-z]+[A-Za-z0-9]*\+?((\.|\-|\_)?[A-Za-z]+[A-Za-z0-9]*)*)@(([A-Za-z0-9]+)+((\.|\-|\_)?([A-Za-z0-9]+)+)*)+\.([A-Za-z]{2,})+$"
                        if [[ -n ${!OPTIND} && ! ${!OPTIND} =~ ^(\-|\-\-) ]]; then
                            SHARE_EMAIL="${!OPTIND}" && ! [[ ${SHARE_EMAIL} =~ ${EMAIL_REGEX} ]] && printf "\nError: Provided email address for share option is invalid.\n" && exit 1
                            OPTIND=$((OPTIND + 1))
                        fi
                        ;;
                    quiet)
                        QUIET="printCenterQuiet" && CURL_ARGS="-s"
                        ;;
                    verbose)
                        VERBOSE="true"
                        ;;
                    verbose-progress)
                        VERBOSE_PROGRESS="true" && CURL_ARGS=""
                        ;;
                    debug)
                        DEBUG="true"
                        ;;
                    '')
                        shorthelp
                        ;;
                    *)
                        printf '%s: --%s: Unknown option\nTry '"%s -h/--help"' for more information.\n' "${0##*/}" "${OPTARG}" "${0##*/}" && exit 1
                        ;;
                esac
                ;;
            h)
                usage
                ;;
            u)
                update && exit $?
                ;;
            U)
                update uninstall && exit $?
                ;;
            C)
                FOLDERNAME="${OPTARG}"
                ;;
            r)
                checkDefault "${OPTARG}" "ROOTDIR=${OPTARG/default=/}" "UPDATE_DEFAULT_ROOTDIR=updateConfig"
                ;;
            z)
                checkDefault "${OPTARG}" "checkConfig" "${OPTARG/default=/}"
                ;;
            i)
                LOG_FILE_ID="${OPTARG}"
                ;;
            s)
                SKIP_SUBDIRS="true"
                ;;
            p)
                NO_OF_PARALLEL_JOBS="${OPTARG}"
                case "${NO_OF_PARALLEL_JOBS}" in
                    '' | *[!0-9]*)
                        printf "\nError: -p/--parallel value ranges between 1 to 10.\n"
                        exit 1
                        ;;
                    *)
                        [[ ${NO_OF_PARALLEL_JOBS} -gt 10 ]] && { NO_OF_PARALLEL_JOBS=10 || NO_OF_PARALLEL_JOBS="${OPTARG}"; }
                        ;;
                esac
                PARALLEL_UPLOAD="true"
                ;;
            o)
                OVERWRITE="Overwrite" && UPLOAD_METHOD="update"
                ;;
            d)
                SKIP_DUPLICATES="Skip Existing" && UPLOAD_METHOD="update"
                ;;
            f)
                INPUT_ARRAY+=("${OPTARG}")
                ;;
            S)
                # https://stackoverflow.com/a/57295993
                # Optional arguments # https://stackoverflow.com/questions/402377/using-getopts-to-process-long-and-short-command-line-options/28466267#28466267
                EMAIL_REGEX="^([A-Za-z]+[A-Za-z0-9]*\+?((\.|\-|\_)?[A-Za-z]+[A-Za-z0-9]*)*)@(([A-Za-z0-9]+)+((\.|\-|\_)?([A-Za-z0-9]+)+)*)+\.([A-Za-z]{2,})+$"
                if [[ -n ${!OPTIND} && ! ${!OPTIND} =~ ^(\-|\-\-) ]]; then
                    SHARE_EMAIL="${!OPTIND}" && ! [[ ${SHARE_EMAIL} =~ ${EMAIL_REGEX} ]] && printf "\nError: Provided email address for share option is invalid.\n" && exit 1
                    OPTIND=$((OPTIND + 1))
                fi
                SHARE=" (SHARED)"
                ;;
            q)
                QUIET="printCenterQuiet" && CURL_ARGS="-s"
                ;;
            v)
                VERBOSE="true"
                ;;
            V)
                VERBOSE_PROGRESS="true" && CURL_ARGS=""
                ;;
            D)
                DEBUG="true"
                ;;
            :)
                printf '%s: -%s: option requires an argument\nTry '"%s -h/--help"' for more information.\n' "${0##*/}" "${OPTARG}" "${0##*/}" && exit 1
                ;;
            ?)
                printf '%s: -%s: Unknown option\nTry '"%s -h/--help"' for more information.\n' "${0##*/}" "${OPTARG}" "${0##*/}" && exit 1
                ;;
        esac
    done
    shift $((OPTIND - 1))

    # Incase ${1} argument was not taken as input, check if any arguments after all the valid flags have been passed, for INPUT and FOLDERNAME.
    # Also check, if folder or dir, else exit.
    if [[ -z ${INPUT_ARRAY[0]} ]]; then
        if [[ -n ${1} && -f ${1} || -d ${1} ]]; then
            FINAL_INPUT_ARRAY+=("${1}")
            { [[ -n ${2} && ${2} != -* ]] && FOLDER_INPUT="${2}"; } || :
        elif [[ -z ${FOLDERNAME} ]]; then
            shortHelp
        fi
    else
        for array in "${INPUT_ARRAY[@]}"; do
            { [[ -f ${array} || -d ${array} ]] && FINAL_INPUT_ARRAY+=("${array[@]}"); } || {
                printf "\nError: Invalid Input ( %s ), no such file or directory.\n" "${array}"
                exit 1
            }
        done
    fi
    mapfile -t FINAL_INPUT_ARRAY <<< "$(removeArrayDuplicates "${FINAL_INPUT_ARRAY[@]}")"

    # Get foldername, prioritise the input given by -C/--create-dir option.
    { [[ -n ${FOLDER_INPUT} && -z ${FOLDERNAME} ]] && FOLDERNAME="${FOLDER_INPUT}"; } || :

    { [[ -n ${VERBOSE_PROGRESS} && -n ${VERBOSE} ]] && unset "${VERBOSE}"; } || :
}

# To avoid spamming in debug mode.
checkDebug() {
    printCenterQuiet() { { [[ $# = 3 ]] && printf "%s\n" "${2}"; } || { printf "%s%s\n" "${2}" "${3}"; }; }
    if [[ -n ${DEBUG} ]]; then
        set -x
        printCenter() { { [[ $# = 3 ]] && printf "%s\n" "${2}"; } || { printf "%s%s\n" "${2}" "${3}"; }; }
        clearLine() { :; } && newLine() { :; }
    else
        set +x
        if [[ -z ${QUIET} ]]; then
            if isTerminal; then
                # This refreshes the interactive shell so we can use the ${COLUMNS} variable in the printCenter function.
                shopt -s checkwinsize && (: && :)
                if [[ ${COLUMNS} -lt 40 ]]; then
                    printCenter() { { [[ $# = 3 ]] && printf "%s\n" "[ ${2} ]"; } || { printf "%s\n" "[ ${2}${3} ]"; }; }
                else
                    trap 'shopt -s checkwinsize; (:;:)' SIGWINCH
                fi
            else
                printCenter() { { [[ $# = 3 ]] && printf "%s\n" "[ ${2} ]"; } || { printf "%s\n" "[ ${2}${3} ]"; }; }
                clearLine() { :; }
            fi
            newLine() { printf "%b" "${1}"; }
        else
            printCenter() { :; } && clearLine() { :; } && newLine() { :; }
        fi
    fi
}

# If internet connection is not available.
# Probably the fastest way, takes about 1 - 2 KB of data, don't check for more than 10 secs.
# curl -m option is unreliable in some cases.
# https://unix.stackexchange.com/a/18711 to timeout without any external program.
checkInternet() {
    printCenter "justify" "Checking Internet connection.." "-"
    if isTerminal; then
        CHECK_INTERNET="$(sh -ic 'exec 3>&1 2>/dev/null; { curl --compressed -Is google.com 1>&3; kill 0; } | { sleep 10; kill 0; }' || :)"
    else
        CHECK_INTERNET="$(curlCmd -s -I google.com -m 10)"
    fi
    clearLine 1
    if [[ -z ${CHECK_INTERNET} ]]; then
        newLine "\n" && printCenter "justify" "Error: Internet connection not available" "="
        exit 1
    fi
}

# Set the path and random name for temp file ( used for showing parallel uploads progress ).
setupTempfile() {
    type -p mktemp &> /dev/null && { TMPFILE="$(mktemp -u)" || TMPFILE="${PWD}/$((RANDOM * 2)).LOG"; }
    trap 'rm -f "${TMPFILE}"SUCCESS ; rm -f "${TMPFILE}"ERROR' EXIT
}

# Credentials
checkCredentials() {
    # shellcheck source=/dev/null
    # Config file is created automatically after first run
    if [[ -r ${CONFIG} ]]; then
        source "${CONFIG}"
        if [[ -n ${UPDATE_DEFAULT_CONFIG} ]]; then
            printf "%s\n" "${CONFIG}" >| "${INFO_PATH}/google-drive-upload.configpath"
        fi
    fi

    [[ -z ${CLIENT_ID} ]] && read -r -p "Client ID: " CLIENT_ID && {
        [[ -z ${CLIENT_ID} ]] && printf "Error: No value provided.\n" 1>&2 && exit 1
        updateConfig CLIENT_ID "${CLIENT_ID}" "${CONFIG}"
    }

    [[ -z ${CLIENT_SECRET} ]] && read -r -p "Client Secret: " CLIENT_SECRET && {
        [[ -z ${CLIENT_SECRET} ]] && printf "Error: No value provided.\n" 1>&2 && exit 1
        updateConfig CLIENT_SECRET "${CLIENT_SECRET}" "${CONFIG}"
    }

    # Method to obtain refresh_token.
    # Requirements: client_id, client_secret and authorization code.
    if [[ -z ${REFRESH_TOKEN} ]]; then
        read -r -p "If you have a refresh token generated, then type the token, else leave blank and press return key..
    Refresh Token: " REFRESH_TOKEN && REFRESH_TOKEN="${REFRESH_TOKEN//[[:space:]]/}"
        if [[ -n ${REFRESH_TOKEN} ]]; then
            updateConfig REFRESH_TOKEN "${REFRESH_TOKEN}" "${CONFIG}"
        else
            printf "\nVisit the below URL, tap on allow and then enter the code obtained:\n"
            URL="https://accounts.google.com/o/oauth2/auth?client_id=${CLIENT_ID}&redirect_uri=${REDIRECT_URI}&scope=${SCOPE}&response_type=code&prompt=consent"
            printf "%s\n" "${URL}" && read -r -p "Enter the authorization code: " CODE
            CODE="${CODE//[[:space:]]/}"
            if [[ -n ${CODE} ]]; then
                RESPONSE="$(curlCmd -s -X POST \
                    --data "code=${CODE}&client_id=${CLIENT_ID}&client_secret=${CLIENT_SECRET}&redirect_uri=${REDIRECT_URI}&grant_type=authorization_code" "${TOKEN_URL}")"

                ACCESS_TOKEN="$(jsonValue access_token <<< "${RESPONSE}")"
                REFRESH_TOKEN="$(jsonValue refresh_token <<< "${RESPONSE}")"

                if [[ -n ${ACCESS_TOKEN} && -n ${REFRESH_TOKEN} ]]; then
                    updateConfig REFRESH_TOKEN "${REFRESH_TOKEN}" "${CONFIG}"
                    updateConfig ACCESS_TOKEN "${ACCESS_TOKEN}" "${CONFIG}"
                else
                    printf "Error: Wrong code given, make sure you copy the exact code.\n"
                    exit 1
                fi
            else
                printf "\n"
                printCenter "normal" "No code provided, run the script and try again" " "
                exit 1
            fi
        fi
    fi

    # Method to regenerate access_token ( also updates in config ).
    # Make a request on https://www.googleapis.com/oauth2/""${API_VERSION}""/tokeninfo?access_token=${ACCESS_TOKEN} url and check if the given token is valid, if not generate one.
    # Requirements: Refresh Token
    getTokenandUpdate() {
        RESPONSE="$(curlCmd -s -X POST --data "client_id=${CLIENT_ID}&client_secret=${CLIENT_SECRET}&refresh_token=${REFRESH_TOKEN}&grant_type=refresh_token" "${TOKEN_URL}")"
        ACCESS_TOKEN="$(jsonValue access_token <<< "${RESPONSE}")"
        updateConfig ACCESS_TOKEN "${ACCESS_TOKEN}" "${CONFIG}"
    }
    if [[ -z ${ACCESS_TOKEN} ]]; then
        getTokenandUpdate
    elif curlCmd -s "${API_URL}/oauth2/""${API_VERSION}""/tokeninfo?access_token=${ACCESS_TOKEN}" | jsonValue error_description &> /dev/null; then
        getTokenandUpdate
    fi
}

# Setup root directory where all file/folders will be uploaded.
setupRootdir() {
    checkROOTID() {
        ROOT_FOLDER="$(driveInfo "$(extractID "${ROOT_FOLDER}")" "id" "${ACCESS_TOKEN}")" || {
            { [[ ${ROOT_FOLDER} =~ "File not found" ]] && "${QUIET:-printCenter}" "justify" "Given root folder " " ID/URL invalid." "="; } || { printf "%s\n" "${ROOT_FOLDER}"; }
            exit 1
        }
        if [[ -n ${ROOT_FOLDER} ]]; then
            "${1:-updateConfig}" ROOT_FOLDER "${ROOT_FOLDER}" "${CONFIG}"
        else
            "${QUIET:-printCenter}" "justify" "Given root folder " " ID/URL invalid." "="
            exit 1
        fi
    }
    if [[ -n ${ROOTDIR} ]]; then
        ROOT_FOLDER="${ROOTDIR//[[:space:]]/}"
        { [[ -n ${ROOT_FOLDER} ]] && checkROOTID "${UPDATE_DEFAULT_ROOTDIR}"; } || :
    elif [[ -z ${ROOT_FOLDER} ]]; then
        read -r -p "Root Folder ID or URL (Default: root): " ROOT_FOLDER
        ROOT_FOLDER="${ROOT_FOLDER//[[:space:]]/}"
        if [[ -n ${ROOT_FOLDER} ]]; then
            checkROOTID
        else
            ROOT_FOLDER="root"
            updateConfig ROOT_FOLDER "${ROOT_FOLDER}" "${CONFIG}"
        fi
    fi
}

# Check to find whether the folder exists in google drive. If not then the folder is created in google drive under the configured root folder.
setupWorkspace() {
    if [[ -z ${FOLDERNAME} ]]; then
        WORKSPACE_FOLDER_ID="${ROOT_FOLDER}"
    else
        WORKSPACE_FOLDER_ID="$(createDirectory "${FOLDERNAME}" "${ROOT_FOLDER}" "${ACCESS_TOKEN}")"
    fi
    WORKSPACE_FOLDER_NAME="$(driveInfo "${WORKSPACE_FOLDER_ID}" name "${ACCESS_TOKEN}")"
}

# Loop through all the input.
processArguments() {
    for INPUT in "${FINAL_INPUT_ARRAY[@]}"; do
        # Check if the argument is a file or a directory.
        if [[ -f ${INPUT} ]]; then
            printCenter "justify" "Given Input" ": FILE" "="
            printCenter "justify" "Upload Method" ": ${SKIP_DUPLICATES:-${OVERWRITE:-Create}}" "=" && newLine "\n"
            uploadFile "${UPLOAD_METHOD:-create}" "${INPUT}" "${WORKSPACE_FOLDER_ID}" "${ACCESS_TOKEN}"
            FILE_ID="${SKIP_DUPLICATES_FILE_ID:-${FILE_ID}}"
            [[ ${UPLOAD_STATUS} = ERROR ]] && for _ in {1..2}; do clearLine 1; done && continue
            if [[ -n "${SHARE}" ]]; then
                printCenter "justify" "Sharing the file.." "-"
                if SHARE_MSG="$(shareID "${FILE_ID}" "${ACCESS_TOKEN}" "${SHARE_EMAIL}")"; then
                    printf "%s\n" "${SHARE_MSG}"
                else
                    clearLine 1
                fi
            fi
            printCenter "justify" "DriveLink" "${SHARE:-}" "-"
            isTerminal && printCenter "normal" "$(printf "\xe2\x86\x93 \xe2\x86\x93 \xe2\x86\x93\n")" " "
            printCenter "normal" "${FILE_LINK}" " "
            printf "\n"
        elif [[ -d ${INPUT} ]]; then
            INPUT="$(cd "${INPUT}" && pwd)" # to handle dirname when current directory (.) is given as input.
            unset EMPTY                     # Used when input folder is empty
            parallel="${PARALLEL_UPLOAD:-}" # Unset PARALLEL value if input is file, for preserving the logging output.

            printCenter "justify" "Upload Method" ": ${SKIP_DUPLICATES:-${OVERWRITE:-Create}}" "="
            printCenter "justify" "Given Input" ": FOLDER" "-" && newLine "\n"
            FOLDER_NAME="${INPUT##*/}" && printCenter "justify" "Folder: ${FOLDER_NAME}" "="

            NEXTROOTDIRID="${WORKSPACE_FOLDER_ID}"

            # Skip the sub folders and find recursively all the files and upload them.
            if [[ -n ${SKIP_SUBDIRS} ]]; then
                printCenter "justify" "Indexing files recursively.." "-"
                mapfile -t FILENAMES <<< "$(find "${INPUT}" -type f)"
                if [[ -n ${FILENAMES[0]} ]]; then
                    NO_OF_FILES="${#FILENAMES[@]}"
                    for _ in {1..2}; do clearLine 1; done
                    "${QUIET:-printCenter}" "justify" "Folder: ${FOLDER_NAME} " "| ${NO_OF_FILES} File(s)" "=" && printf "\n"
                    printCenter "justify" "Creating folder.." "-"
                    ID="$(createDirectory "${INPUT}" "${NEXTROOTDIRID}" "${ACCESS_TOKEN}")" && clearLine 1
                    DIRIDS[1]="${ID}"
                    if [[ -n ${parallel} ]]; then
                        { [[ ${NO_OF_PARALLEL_JOBS} -gt ${NO_OF_FILES} ]] && NO_OF_PARALLEL_JOBS_FINAL="${NO_OF_FILES}"; } || { NO_OF_PARALLEL_JOBS_FINAL="${NO_OF_PARALLEL_JOBS}"; }
                        # Export because xargs cannot access if it is just an internal variable.
                        export ID CURL_ARGS="-s" ACCESS_TOKEN STRING OVERWRITE COLUMNS API_URL API_VERSION LOG_FILE_ID SKIP_DUPLICATES QUIET UPLOAD_METHOD
                        export -f uploadFile printCenter clearLine jsonValue urlEncode checkExistingFile printCenterQuiet newLine bytesToHuman curlCmd

                        [[ -f ${TMPFILE}SUCCESS ]] && rm "${TMPFILE}"SUCCESS
                        [[ -f ${TMPFILE}ERROR ]] && rm "${TMPFILE}"ERROR

                        # shellcheck disable=SC2016
                        printf "%s\n" "${FILENAMES[@]}" | xargs -n1 -P"${NO_OF_PARALLEL_JOBS_FINAL}" -i bash -c '
                        uploadFile "${UPLOAD_METHOD:-create}" "{}" "${ID}" "${ACCESS_TOKEN}" parallel
                        ' 1>| "${TMPFILE}"SUCCESS 2>| "${TMPFILE}"ERROR &

                        while true; do [[ -f "${TMPFILE}"SUCCESS || -f "${TMPFILE}"ERROR ]] && { break || bashSleep 0.5; }; done

                        newLine "\n"
                        ERROR_STATUS=0 SUCCESS_STATUS=0
                        while true; do
                            SUCCESS_STATUS="$(count < "${TMPFILE}"SUCCESS)"
                            ERROR_STATUS="$(count < "${TMPFILE}"ERROR)"
                            bashSleep 1
                            if [[ $(((SUCCESS_STATUS + ERROR_STATUS))) != "${TOTAL}" ]]; then
                                clearLine 1 && "${QUIET:-printCenter}" "justify" "Status" ": ${SUCCESS_STATUS} Uploaded | ${ERROR_STATUS} Failed" "="
                            fi
                            TOTAL="$(((SUCCESS_STATUS + ERROR_STATUS)))"
                            [[ ${TOTAL} = "${NO_OF_FILES}" ]] && break
                        done
                        for _ in {1..2}; do clearLine 1; done
                        [[ -z ${VERBOSE} && -z ${VERBOSE_PROGRESS} ]] && newLine "\n\n"
                    else
                        [[ -z ${VERBOSE} && -z ${VERBOSE_PROGRESS} ]] && newLine "\n"

                        ERROR_STATUS=0 SUCCESS_STATUS=0
                        for file in "${FILENAMES[@]}"; do
                            DIRTOUPLOAD="${ID}"
                            uploadFile "${UPLOAD_METHOD:-create}" "${file}" "${DIRTOUPLOAD}" "${ACCESS_TOKEN}"
                            [[ ${UPLOAD_STATUS} = ERROR ]] && ERROR_STATUS="$((ERROR_STATUS + 1))" || SUCCESS_STATUS="$((SUCCESS_STATUS + 1))" || :
                            if [[ -n ${VERBOSE:-${VERBOSE_PROGRESS}} ]]; then
                                printCenter "justify" "Status: ${SUCCESS_STATUS} Uploaded" " | ${ERROR_STATUS} Failed" "=" && newLine "\n"
                            else
                                for _ in {1..2}; do clearLine 1; done
                                printCenter "justify" "Status: ${SUCCESS_STATUS} Uploaded" " | ${ERROR_STATUS} Failed" "="
                            fi
                        done
                    fi
                else
                    newLine "\n" && EMPTY=1
                fi
            else
                printCenter "justify" "Indexing files/sub-folders" " recursively.." "-"
                # Do not create empty folders during a recursive upload. Use of find in this section is important.
                mapfile -t DIRNAMES <<< "$(find "${INPUT}" -type d -not -empty)"
                NO_OF_FOLDERS="${#DIRNAMES[@]}" && NO_OF_SUB_FOLDERS="$((NO_OF_FOLDERS - 1))"
                # Create a loop and make folders according to list made above.
                if [[ ${NO_OF_SUB_FOLDERS} != 0 ]]; then
                    clearLine 1
                    printCenter "justify" "${NO_OF_SUB_FOLDERS} Sub-folders found." "="
                fi
                printCenter "justify" "Indexing files.." "="
                mapfile -t FILENAMES <<< "$(find "${INPUT}" -type f)"
                if [[ -n ${FILENAMES[0]} ]]; then
                    NO_OF_FILES="${#FILENAMES[@]}"
                    for _ in {1..3}; do clearLine 1; done
                    if [[ ${NO_OF_SUB_FOLDERS} != 0 ]]; then
                        "${QUIET:-printCenter}" "justify" "${FOLDER_NAME} " "| ${NO_OF_FILES} File(s) | ${NO_OF_SUB_FOLDERS} Sub-folders" "="
                    else
                        "${QUIET:-printCenter}" "justify" "${FOLDER_NAME} " "| ${NO_OF_FILES} File(s)" "="
                    fi
                    newLine "\n"
                    printCenter "justify" "Creating Folder(s).." "-"
                    { [[ ${NO_OF_SUB_FOLDERS} != 0 ]] && newLine "\n"; } || :

                    unset status DIRIDS
                    for dir in "${DIRNAMES[@]}"; do
                        if [[ -n ${status} ]]; then
                            __dir="$(dirname "${dir}")"
                            __temp="$(printf "%s\n" "${DIRIDS[@]}" | grep "|:_//_:|${__dir}|:_//_:|")"
                            NEXTROOTDIRID="$(printf "%s\n" "${__temp//"|:_//_:|"${__dir}*/}")"
                        fi
                        NEWDIR="${dir##*/}"
                        [[ ${NO_OF_SUB_FOLDERS} != 0 ]] && printCenter "justify" "Name: ${NEWDIR}" "-"
                        ID="$(createDirectory "${NEWDIR}" "${NEXTROOTDIRID}" "${ACCESS_TOKEN}")"
                        # Store sub-folder directory IDs and it's path for later use.
                        ((status += 1))
                        DIRIDS[${status}]="$(printf "%s|:_//_:|%s|:_//_:|\n" "${ID}" "${dir}" && printf "\n")"
                        if [[ ${NO_OF_SUB_FOLDERS} != 0 ]]; then
                            for _ in {1..2}; do clearLine 1; done
                            printCenter "justify" "Status" ": ${status} / ${NO_OF_FOLDERS}" "="
                        fi
                    done

                    if [[ ${NO_OF_SUB_FOLDERS} != 0 ]]; then
                        for _ in {1..2}; do clearLine 1; done
                    else
                        clearLine 1
                    fi
                    printCenter "justify" "Preparing to upload.." "-"

                    unset status
                    for file in "${FILENAMES[@]}"; do
                        __rootdir="$(dirname "${file}")"
                        ((status += 1))
                        FINAL_LIST[${status}]="$(printf "%s\n" "${__rootdir}|:_//_:|$(__temp="$(printf "%s\n" "${DIRIDS[@]}" | grep "|:_//_:|${__rootdir}|:_//_:|")" &&
                            printf "%s\n" "${__temp//"|:_//_:|"${__rootdir}*/}")|:_//_:|${file}")"
                    done

                    if [[ -n ${parallel} ]]; then
                        { [[ ${NO_OF_PARALLEL_JOBS} -gt ${NO_OF_FILES} ]] && NO_OF_PARALLEL_JOBS_FINAL="${NO_OF_FILES}"; } || { NO_OF_PARALLEL_JOBS_FINAL="${NO_OF_PARALLEL_JOBS}"; }
                        # Export because xargs cannot access if it is just an internal variable.
                        export CURL_ARGS="-s" ACCESS_TOKEN STRING OVERWRITE COLUMNS API_URL API_VERSION LOG_FILE_ID SKIP_DUPLICATES QUIET UPLOAD_METHOD
                        export -f uploadFile printCenter clearLine jsonValue urlEncode checkExistingFile printCenterQuiet newLine bytesToHuman curlCmd

                        [[ -f "${TMPFILE}"SUCCESS ]] && rm "${TMPFILE}"SUCCESS
                        [[ -f "${TMPFILE}"ERROR ]] && rm "${TMPFILE}"ERROR

                        # shellcheck disable=SC2016
                        printf "%s\n" "${FINAL_LIST[@]}" | xargs -n1 -P"${NO_OF_PARALLEL_JOBS_FINAL}" -i bash -c '
                        LIST="{}"
                        FILETOUPLOAD="${LIST//*"|:_//_:|"}"
                        DIRTOUPLOAD="$(: "|:_//_:|""${FILETOUPLOAD}" && : "${LIST::-${#_}}" && printf "%s\n" "${_//*"|:_//_:|"}")"
                        uploadFile "${UPLOAD_METHOD:-create}" "${FILETOUPLOAD}" "${DIRTOUPLOAD}" "${ACCESS_TOKEN}" parallel
                        ' 1>| "${TMPFILE}"SUCCESS 2>| "${TMPFILE}"ERROR &

                        while true; do [[ -f "${TMPFILE}"SUCCESS || -f "${TMPFILE}"ERROR ]] && { break || bashSleep 0.5; }; done

                        clearLine 1 && newLine "\n"
                        while true; do
                            SUCCESS_STATUS="$(count < "${TMPFILE}"SUCCESS)"
                            ERROR_STATUS="$(count < "${TMPFILE}"ERROR)"
                            bashSleep 1
                            if [[ $(((SUCCESS_STATUS + ERROR_STATUS))) != "${TOTAL}" ]]; then
                                clearLine 1 && "${QUIET:-printCenter}" "justify" "Status" ": ${SUCCESS_STATUS} Uploaded | ${ERROR_STATUS} Failed" "="
                            fi
                            TOTAL="$(((SUCCESS_STATUS + ERROR_STATUS)))"
                            [[ ${TOTAL} = "${NO_OF_FILES}" ]] && break
                        done
                        clearLine 1

                        [[ -z ${VERBOSE} && -z ${VERBOSE_PROGRESS} ]] && newLine "\n"
                    else
                        clearLine 1 && newLine "\n"
                        ERROR_STATUS=0 SUCCESS_STATUS=0
                        for LIST in "${FINAL_LIST[@]}"; do
                            FILETOUPLOAD="${LIST//*"|:_//_:|"/}"
                            DIRTOUPLOAD="$(: "|:_//_:|""${FILETOUPLOAD}" && : "${LIST::-${#_}}" && printf "%s\n" "${_//*"|:_//_:|"/}")"
                            uploadFile "${UPLOAD_METHOD:-create}" "${FILETOUPLOAD}" "${DIRTOUPLOAD}" "${ACCESS_TOKEN}"
                            [[ ${UPLOAD_STATUS} = ERROR ]] && ERROR_STATUS="$((ERROR_STATUS + 1))" || SUCCESS_STATUS="$((SUCCESS_STATUS + 1))" || :
                            if [[ -n ${VERBOSE:-${VERBOSE_PROGRESS}} ]]; then
                                printCenter "justify" "Status" ": ${SUCCESS_STATUS} Uploaded | ${ERROR_STATUS} Failed" "=" && newLine "\n"
                            else
                                for _ in {1..2}; do clearLine 1; done
                                printCenter "justify" "Status" ": ${SUCCESS_STATUS} Uploaded | ${ERROR_STATUS} Failed" "="
                            fi
                        done
                    fi
                else
                    EMPTY=1
                fi
            fi
            if [[ ${EMPTY} != 1 ]]; then
                [[ -z ${VERBOSE} && -z ${VERBOSE_PROGRESS} ]] && for _ in {1..2}; do clearLine 1; done

                if [[ ${SUCCESS_STATUS} -gt 0 ]]; then
                    if [[ -n ${SHARE} ]]; then
                        printCenter "justify" "Sharing the folder.." "-"
                        if SHARE_MSG="$(shareID "$(read -r firstline <<< "${DIRIDS[1]}" && printf "%s\n" "${firstline/"|:_//_:|"*/}")" "${ACCESS_TOKEN}" "${SHARE_EMAIL}")"; then
                            printf "%s\n" "${SHARE_MSG}"
                        else
                            clearLine 1
                        fi
                    fi
                    printCenter "justify" "FolderLink" "${SHARE:-}" "-"
                    isTerminal && printCenter "normal" "$(printf "\xe2\x86\x93 \xe2\x86\x93 \xe2\x86\x93\n")" " "
                    printCenter "normal" "$(: "$(read -r firstline <<< "${DIRIDS[1]}" &&
                        printf "%s\n" "${firstline/"|:_//_:|"*/}")" && printf "%s\n" "${_/$_/https://drive.google.com/open?id=$_}")" " "
                fi
                newLine "\n"
                [[ ${SUCCESS_STATUS} -gt 0 ]] && "${QUIET:-printCenter}" "justify" "Total Files " "Uploaded: ${SUCCESS_STATUS}" "="
                [[ ${ERROR_STATUS} -gt 0 ]] && "${QUIET:-printCenter}" "justify" "Total Files " "Failed: ${ERROR_STATUS}" "="
                printf "\n"
            else
                for _ in {1..2}; do clearLine 1; done
                "${QUIET:-printCenter}" 'justify' "Empty Folder." "-"
                printf "\n"
            fi
        fi
    done
}

main() {
    [[ $# = 0 ]] && shortHelp

    trap 'exit "$?"' INT TERM && trap 'exit "$?"' EXIT

    checkBashVersion && set -o errexit -o noclobber -o pipefail

    setupArguments "${@}"
    checkDebug && checkInternet
    setupTempfile

    START=$(printf "%(%s)T\\n" "-1")
    printCenter "justify" "Starting script" "-"

    printCenter "justify" "Checking credentials.." "-"
    checkCredentials && for _ in {1..2}; do clearLine 1; done
    printCenter "justify" "Required credentials available." "-"

    printCenter "justify" "Checking root dir and workspace folder.." "-"
    setupRootdir && for _ in {1..2}; do clearLine 1; done
    printCenter "justify" "Root dir properly configured." "-"

    printCenter "justify" "Checking Workspace Folder.." "-"
    setupWorkspace && for _ in {1..2}; do clearLine 1; done
    printCenter "justify" "Workspace Folder: ${WORKSPACE_FOLDER_NAME}" "="
    printCenter "normal" " ${WORKSPACE_FOLDER_ID} " "-" && newLine "\n"

    processArguments

    END="$(printf "%(%s)T\\n" "-1")"
    DIFF="$((END - START))"
    "${QUIET:-printCenter}" "normal" " Time Elapsed: ""$((DIFF / 60))"" minute(s) and ""$((DIFF % 60))"" seconds. " "="
}

main "${@}"
