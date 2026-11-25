"""Register the fax identifier and install its App Store profile for this build."""
import base64
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile

BUNDLE = 'com.korlixdeveloper.fax'
PROFILE_NAME = 'Fax by Korlix App Store'


def apple(*args):
    result = subprocess.run(['app-store-connect', *args, '--json', '--no-color',
                             '--log-stream', 'stderr'], check=True, stdout=subprocess.PIPE)
    return json.loads(result.stdout)


def checked_profile(profile, certificate):
    with tempfile.TemporaryDirectory() as folder:
        file = Path(folder) / 'fax.mobileprovision'
        content = base64.b64decode(profile['attributes']['profileContent'], validate=True)
        file.write_bytes(content)
        decoded = plistlib.loads(subprocess.check_output(['security', 'cms', '-D', '-i', str(file)]))
    entitlement = decoded['Entitlements']
    if (entitlement['application-identifier'] != decoded['ApplicationIdentifierPrefix'][0] + '.' + BUNDLE
            or certificate not in decoded['DeveloperCertificates'] or entitlement.get('get-task-allow')
            or decoded.get('ProvisionedDevices') or decoded.get('ProvisionsAllDevices')):
        raise ValueError('The profile must match the fax bundle and existing distribution certificate.')
    return content, decoded['UUID']


def main():
    installed = subprocess.check_output(['security', 'find-identity', '-v', '-p', 'codesigning'], text=True)
    fingerprints = set(re.findall(r'\b([0-9A-F]{40})\s+"(?:Apple|iPhone) Distribution:', installed))
    certs = []
    for cert in apple('certificates', 'list', '--profile-type', 'IOS_APP_STORE'):
        der = base64.b64decode(cert['attributes']['certificateContent'], validate=True)
        if hashlib.sha1(der).hexdigest().upper() in fingerprints:
            certs.append((der, cert['id']))
    if len(certs) != 1:
        raise ValueError('Expected the existing Korlix distribution certificate in the signing keychain.')
    der, cert_id = certs[0]
    bundles = apple('bundle-ids', 'list', '--bundle-id-identifier', BUNDLE, '--strict-match-identifier')
    if not bundles:
        bundles = [apple('bundle-ids', 'create', BUNDLE, '--name', 'Fax by Korlix')]
    if len(bundles) != 1 or bundles[0]['attributes']['identifier'] != BUNDLE:
        raise ValueError('Apple did not return the unique fax bundle identifier.')
    bundle_id = bundles[0]['id']
    active = apple('bundle-ids', 'profiles', '--bundle-ids', bundle_id, '--type', 'IOS_APP_STORE', '--state', 'ACTIVE')
    matching = [p for p in active if p['attributes']['name'] == PROFILE_NAME]
    if not matching:
        matching = [apple('profiles', 'create', bundle_id, '--certificate-ids', cert_id,
                          '--type', 'IOS_APP_STORE', '--name', PROFILE_NAME)]
    data, uid = checked_profile(matching[0], der)
    destination = Path.home() / 'Library/MobileDevice/Provisioning Profiles'
    destination.mkdir(exist_ok=True, parents=True)
    (destination / (uid + '.mobileprovision')).write_bytes(data)
    Path('ios/fax.mobileprovision').write_bytes(data)
    print('Verified the Fax by Korlix App Store profile with the existing Korlix distribution certificate.')


if __name__ == '__main__':
    main()
