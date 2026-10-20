#!/usr/bin/env python3
"""Install existing Core ML .mlpackage models into this Xcode project.
No model conversion or training. Pre-registered Xcode resource entries exist.
"""
from pathlib import Path
import argparse
import os
import shutil
import sys
import tempfile
import zipfile

ROOT=Path(__file__).resolve().parent
DEST=ROOT/'RodentStudio'/'Resources'/'Models'
HOME=Path.home()
# Reuse the two *identical* Core ML packages already installed into yesterday's 0.6.0.
PREVIOUS=HOME/'Downloads'/'RodentStudio-Final'/'RodentStudio-0.6.0'/'RodentStudio'/'Resources'/'Models'
MOUSE_SOURCES=[
 PREVIOUS/'MousePose6_960_int8.mlpackage',
 HOME/'Downloads'/'rodent-desktop'/'models'/'source'/'MousePose6_960_int8.mlpackage',
 HOME/'Downloads'/'rodent-desktop-0.2.0'/'rodent-desktop'/'models'/'source'/'MousePose6_960_int8.mlpackage',
]
CYLINDER_SOURCES=[
 PREVIOUS/'CylinderMousePoseV2.mlpackage',
 HOME/'Downloads'/'07_export'/'CylinderMousePoseV2.mlpackage.zip',
 HOME/'Downloads'/'rodent-desktop'/'models'/'user_supplied'/'cylinder_v2'/'CylinderMousePoseV2.mlpackage.zip',
]

def validate(root: Path):
    if not (root/'Manifest.json').is_file():
        raise ValueError(f'Not a complete Core ML package: missing Manifest.json: {root}')
    mlmodels=list(root.rglob('*.mlmodel'))
    if not mlmodels:
        raise ValueError(f'Not a complete Core ML package: missing .mlmodel: {root}')

def safe_unzip(path: Path, destination: Path, name: str):
    with zipfile.ZipFile(path) as z:
        fs=[i for i in z.infolist() if not i.is_dir()]
        candidates=[]
        for i in fs:
            pp=Path(i.filename)
            if pp.is_absolute() or '..' in pp.parts or i.filename.startswith('\\'):
                raise ValueError(f'Unsafe ZIP member {i.filename}')
            if i.filename.endswith('/Manifest.json') and any(c.endswith('.mlpackage') for c in pp.parts[:-1]):
                k=next(j for j,c in enumerate(pp.parts[:-1]) if c.endswith('.mlpackage'))
                candidates.append(pp.parts[:k+1])
        unique={tuple(c) for c in candidates}
        if len(unique)!=1:
            raise ValueError(f'Expected exactly one .mlpackage root, found {len(unique)}')
        prefix=next(iter(unique))
        for member in fs:
            pp=Path(member.filename)
            if tuple(pp.parts[:len(prefix)])!=prefix: continue
            sub=pp.parts[len(prefix):]
            if not sub: continue
            # No symlinks or executable content from an untrusted archive.
            mode=(member.external_attr>>16)&0o170000
            if mode==0o120000: raise ValueError('Symlinks not allowed in model ZIP')
            out=destination.joinpath(*sub)
            out.parent.mkdir(parents=True, exist_ok=True)
            with z.open(member) as fi, out.open('wb') as fo:
                shutil.copyfileobj(fi,fo)

def install(source: Path, name: str):
    target=DEST/name
    if target.exists():
        validate(target)
        print(f'ALREADY PRESENT {target}')
        return
    with tempfile.TemporaryDirectory(prefix='rodent-model-') as temp:
        stage=Path(temp)/name
        if source.is_dir() and source.name.endswith('.mlpackage'):
            shutil.copytree(source,stage)
        elif source.is_file() and source.name.endswith('.zip'):
            stage.mkdir(parents=True)
            safe_unzip(source,stage,name)
        else:
            raise ValueError(f'Expected .mlpackage directory or .zip: {source}')
        validate(stage)
        DEST.mkdir(parents=True,exist_ok=True)
        shutil.move(str(stage),str(target))
    print(f'INSTALLED {target}')

def choose(user, options, key):
    if user:
        src=Path(user).expanduser().resolve()
        if not src.exists(): raise FileNotFoundError(src)
        return src
    for p in options:
        if p.exists():return p
    raise FileNotFoundError(f'{key} source not found. Provide --{key} PATH')

if __name__=='__main__':
    ap=argparse.ArgumentParser()
    ap.add_argument('--mouse',help='MousePose6 .mlpackage directory')
    ap.add_argument('--cylinder',help='Cylinder V2 .mlpackage or .mlpackage.zip')
    ap.add_argument('--only',choices=['mouse','cylinder','both'],default='both')
    args=ap.parse_args()
    try:
        if args.only in ('mouse','both'):
            name='MousePose6_960_int8.mlpackage'
            if (DEST/name).exists():
                validate(DEST/name)
                print(f'ALREADY PRESENT {DEST/name}')
            else:
                install(choose(args.mouse,MOUSE_SOURCES,'mouse'),name)
        if args.only in ('cylinder','both'):
            name='CylinderMousePoseV2.mlpackage'
            if (DEST/name).exists():
                validate(DEST/name)
                print(f'ALREADY PRESENT {DEST/name}')
            else:
                install(choose(args.cylinder,CYLINDER_SOURCES,'cylinder'),name)
        print('SUCCESS: Models copied. Open Xcode, choose My Mac, and Build (⌘B).')
    except Exception as e:
        print(f'ERROR: {e}',file=sys.stderr)
        sys.exit(1)
