#!/usr/bin/env python3
"""Generate an isolated, dependency-free Xcode UI-test project under dist/."""
import json
import os
import plistlib
import subprocess
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'ios/Hub Ball'
OUTPUT = ROOT / 'dist/large-text-ui/Hub Ball.xcodeproj'
OUTPUT.mkdir(parents=True, exist_ok=True)
p = json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(SOURCE / 'Hub Ball.xcodeproj/project.pbxproj')]))
o = p['objects']
project = o[p['rootObject']]
project['projectDirPath'] = ''
for value in o.values():
    if value.get('isa') == 'PBXFileSystemSynchronizedRootGroup':
        value['path'] = str(SOURCE / value['path'])
        value['sourceTree'] = '<absolute>'
    settings = value.get('buildSettings', {})
    if 'INFOPLIST_FILE' in settings:
        settings['INFOPLIST_FILE'] = str(SOURCE / settings['INFOPLIST_FILE'])
app = '8128DAE230464115004B3947'

def obj(n, **fields):
    key = f'ACCE550000000000{n:08X}'
    o[key] = fields
    return key

product = obj(1, isa='PBXFileReference', explicitFileType='wrapper.cfbundle', path='LargeTextUITests.xctest', sourceTree='BUILT_PRODUCTS_DIR')
group = obj(2, isa='PBXFileSystemSynchronizedRootGroup', path=str(SOURCE / 'LargeTextUITests'), sourceTree='<absolute>')
phases = [obj(n, isa=isa, buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0) for n, isa in [(3,'PBXSourcesBuildPhase'), (4,'PBXFrameworksBuildPhase'), (5,'PBXResourcesBuildPhase')]]
configs=[]
for n, name in [(6,'Debug'),(7,'Release')]:
    configs.append(obj(n, isa='XCBuildConfiguration', name=name, buildSettings={
        'PRODUCT_BUNDLE_IDENTIFIER':'com.sfrancoe.HubBall.LargeTextUITests',
        'PRODUCT_NAME':'$(TARGET_NAME)', 'GENERATE_INFOPLIST_FILE':'YES',
        'SWIFT_VERSION':'5.0', 'IPHONEOS_DEPLOYMENT_TARGET':'17.0',
        'TARGETED_DEVICE_FAMILY':'1,2', 'TEST_TARGET_NAME':'Hub Ball',
        'CODE_SIGNING_ALLOWED':'NO', 'SWIFT_STRICT_CONCURRENCY':'minimal',
    }))
config = obj(8, isa='XCConfigurationList', buildConfigurations=configs, defaultConfigurationIsVisible=0, defaultConfigurationName='Debug')
proxy = obj(9, isa='PBXContainerItemProxy', containerPortal=p['rootObject'], proxyType=1, remoteGlobalIDString=app, remoteInfo='Hub Ball')
dep = obj(10, isa='PBXTargetDependency', target=app, targetProxy=proxy)
target = obj(11, isa='PBXNativeTarget', name='LargeTextUITests', productName='LargeTextUITests', productType='com.apple.product-type.bundle.ui-testing', productReference=product, buildConfigurationList=config, buildPhases=phases, buildRules=[], dependencies=[dep], fileSystemSynchronizedGroups=[group])
project['targets'].append(target)
o[project['mainGroup']]['children'].append(group)
o[project['productRefGroup']]['children'].append(product)
project['attributes']['TargetAttributes'][target]={'CreatedOnToolsVersion':'26.6','TestTargetID':app}
(OUTPUT/'project.pbxproj').write_bytes(plistlib.dumps(p))
scheme=ET.parse(SOURCE/'Hub Ball.xcodeproj/xcshareddata/xcschemes/Hub Ball.xcscheme')
ref=dict(BuildableIdentifier='primary',BlueprintIdentifier=target,BuildableName='LargeTextUITests.xctest',BlueprintName='LargeTextUITests',ReferencedContainer='container:Hub Ball.xcodeproj')
entry=ET.SubElement(scheme.find('./BuildAction/BuildActionEntries'),'BuildActionEntry',dict(buildForTesting='YES',buildForRunning='NO',buildForProfiling='NO',buildForArchiving='NO',buildForAnalyzing='YES'))
ET.SubElement(entry,'BuildableReference',ref)
test=scheme.find('./TestAction')
test.attrib.pop('shouldAutocreateTestPlan',None)
for existing in test.findall('Testables'):
    test.remove(existing)
testables=ET.SubElement(test,'Testables')
ET.SubElement(ET.SubElement(testables,'TestableReference',{'skipped':'NO','parallelizable':'NO'}),'BuildableReference',ref)
scheme_path=OUTPUT/'xcshareddata/xcschemes/LargeTextAudit.xcscheme'
scheme_path.parent.mkdir(parents=True,exist_ok=True)
test.set('shouldUseLaunchSchemeArgsEnv', 'NO')
envs = ET.SubElement(test, 'EnvironmentVariables')
ET.SubElement(envs, 'EnvironmentVariable', key='HUB_UI_API_ROOT', value=os.environ.get('HUB_UI_API_ROOT', ''), isEnabled='YES')
ET.SubElement(envs, 'EnvironmentVariable', key='HUB_UI_STORY_ROOT', value=os.environ.get('HUB_UI_STORY_ROOT', ''), isEnabled='YES')
ET.SubElement(envs, 'EnvironmentVariable', key='HUB_UI_UPDATE_ROOT', value=os.environ.get('HUB_UI_UPDATE_ROOT', ''), isEnabled='YES')
ET.SubElement(envs, 'EnvironmentVariable', key='HUB_UI_FEATURED_ROOT', value=os.environ.get('HUB_UI_FEATURED_ROOT', ''), isEnabled='YES')
scheme.write(scheme_path,encoding='utf-8',xml_declaration=True)
ET.SubElement(envs, 'EnvironmentVariable', key='HUBBALL_LIVE_SIZE_TEST', value='1', isEnabled='YES')
scheme.write(scheme_path.with_name('LargeTextLiveSize.xcscheme'), encoding='utf-8', xml_declaration=True)
print(OUTPUT)
