#!/usr/bin/env python3
"""Package reviewed remote-schema JSON as a private binary preview seed. Never publishes."""
import argparse, base64
from pathlib import Path
from featured_story import validate, LIMIT
from story_content import decode, digest, encoded, require, validate_payload, PAYLOAD_LIMIT

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest',type=Path,required=True)
    parser.add_argument('--payload',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    manifest=validate(decode(args.manifest.read_bytes(),LIMIT))
    require(manifest['enabled'],'A preview seed must have a reviewed entry')
    payload=args.payload.read_bytes();require(digest(payload)==manifest['entry']['revision'],'Preview payload integrity mismatch')
    document=validate_payload(decode(payload,PAYLOAD_LIMIT),manifest['entry'])
    if document.get('presentation'):
        require(manifest['expiresAt']<=document['presentation']['hookExpiresAt'],'Opening cannot outlive its time-sensitive hook')
    envelope=encoded({'manifest':manifest,'payloadBase64':base64.b64encode(payload).decode()})
    require(len(envelope)<=750*1024,'Preview envelope too large')
    args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_bytes(envelope)
    print('Prepared private preview seed:',args.output,'No publication performed.')
if __name__=='__main__':main()
