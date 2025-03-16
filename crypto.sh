#!/bin/bash

# constants
USERNAME="kim.s"

# error handling: contains ERROR last.f and prints to stderr
error_exit() {
    echo "ERROR $USERNAME" >&2
    exit 1
}

# input validation - check for mode arg
if [ "$#" -lt 1 ]; then
    error_exit "Invalid arguments: Expected input in the format ./crypto.sh -sender ... or ./crypto.sh -receiver ..."
fi

# set mode
MODE=$1

# sender mode
if [ "$MODE" == "-sender" ]; then

    # input validation
    if [ "$#" -ne 7 ]; then
        error_exit "Invalid number of arguments: command must be in the format ./crypto.sh -sender <receiver1_pub> <receiver2_pub> <receiver3_pub> <sender_priv> <plaintext_file> <zip_filename>"
    fi

    # assign input to consts
    RECEIVER1_PUB=$2
    RECEIVER2_PUB=$3
    RECEIVER3_PUB=$4
    SENDER_PRIV=$5
    PLAINTEXT_FILE=$6
    ZIP_FILE=$7

    # TODO:

    # 1. create random session key
    openssl rand -base64 32 > session.key

    # 2. AES encrypt plaintext file w/ session key
    openssl enc -aes-256-cbc -in "$PLAINTEXT_FILE" -out "${PLAINTEXT_FILE}.enc" -pass file:session.key

    # 3. hash and digitally sign encrypted file w/ sender pvt key
    openssl dgst -sha256 -sign "$SENDER_PRIV" -out "${PLAINTEXT_FILE}.sig" "${PLAINTEXT_FILE}.enc"
    
    # utility for creating unique envelope and zip file
    function envelope_and_zip () {
        r_pub=$1
        s_priv=$2

        # a. create shared secret
        openssl pkeyutl -derive -inkey "$s_priv" -peerkey "$r_pub" -out shared_secret.bin

        # b. derive key from shared secret using pbkdf2 and encrypt session key
        openssl enc -pbkdf2 -aes-256-cbc -salt -in session.key -out "session.key.enc" -pass file:shared_secret.bin

        # c. zip file contains: encrypted file, encrypted file signature, encrypted session key
        zip "$ZIP_FILE" "${PLAINTEXT_FILE}.enc" "{$PLAINTEXT_FILE}.sig" "session.key.enc"

    }

    # 4. create envelope and zip for each receiver:
    envelope_and_zip $RECEIVER1_PUB, $SENDER_PRIV
    envelope_and_zip $RECEIVER2_PUB, $SENDER_PRIV
    envelope_and_zip $RECEIVER3_PUB, $SENDER_PRIV

    # 5. rm temp files
    rm -f session.key shared_secret.bin "${PLAINTEXT_FILE}.enc" "${PLAINTEXT_FILE}.sig" "session.keyu.enc"
    echo "File1 encrpyted and signed to $ZIP_FILE"

# receiver mode
elif [ "$MODE" == "-receiver" ]; then

    # input validation
    if [ "$#" -ne 5 ]; then
        error_exit "Invalid number of arguments: command must be in the format ./crypto.sh -receiver <receiver_priv> <sender_pub> <zip_file> <plaintext_file>"
    fi
    # assign input to consts
    RECEIVER_PRIV=$2
    SENDER_PUB=$3
    ZIP_FILE=$4
    OUTPUT_FILE=$5

    # 1. unzip file
    unzip "$ZIP_FILE" || error_exit "Error occurred while trying to unzip file"

    # 2. create shared secret
    openssl pkeyutl -derive -inkey "$RECEIVER_PRIV" -peerkey "$SENDER_PUB" -out shared_secret.bin

    # 2. derive key and decrypt session key
    openssl enc -d -pbkdf2 -aes-256-cbc -in "session.key.enc" -out session.key -pass file:shared_secret.bin || error_exit "Digital Envelope Decryption failed."

    # 3. decrypt file1
    openssl enc -d -aes-256-cbc -pbkdf2 -in "${OUTPUT_FILE}.enc" -out "$OUTPUT_FILE" -pass file:session.key

    # 4. check hashes to confirm success
    openssl dgst -sha -verify "$SENDER_PUB" -signature "${OUTPUT_FILE}.sig" "${OUTPUT_FILE}.enc" || error_exit "Signature verification failed."

    # 5. rm temp files
    rm -f session.key shared_secret.bin "${OUTPUT_FILE}.enc" "${OUTPUT_FILE}.sig" "session.key.enc"
    echo "File successfully decrypted to $OUTPUT_FILE"


# invalid mode
else
    error_exit "Invalid arguments: command must start with ./crypto.sh -sender or ./crypto.sh -receiver"
fi