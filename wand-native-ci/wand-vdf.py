#!/usr/bin/env python3
import os, re, sys, shutil, tempfile
from collections import OrderedDict

TOKEN_RE = re.compile(r'"((?:\\.|[^"\\])*)"|([{}])|([^\s{}"]+)')

def unescape(s):
    return bytes(s, "utf-8").decode("unicode_escape")

def escape(s):
    return str(s).replace("\\","\\\\").replace('"','\\"').replace("\n","\\n")

def tokenize(text):
    text = re.sub(r'//[^\n]*', '', text)
    out=[]
    for m in TOKEN_RE.finditer(text):
        if m.group(1) is not None:
            out.append(("str", unescape(m.group(1))))
        elif m.group(2):
            out.append((m.group(2), m.group(2)))
        elif m.group(3):
            out.append(("str", m.group(3)))
    return out

def parse(text):
    toks=tokenize(text); i=0
    root=OrderedDict()
    def obj(end_on_brace=False):
        nonlocal i
        d=OrderedDict()
        while i < len(toks):
            typ,val=toks[i]
            if typ == "}":
                if end_on_brace:
                    i+=1
                    return d
                i+=1
                continue
            if typ != "str":
                i+=1; continue
            key=val; i+=1
            if i>=len(toks):
                d[key]=""; break
            typ2,val2=toks[i]
            if typ2 == "{":
                i+=1
                d[key]=obj(True)
            elif typ2 == "str":
                d[key]=val2; i+=1
            else:
                d[key]=""
        return d
    return obj(False)

def dump(d, depth=0):
    lines=[]
    ind="\t"*depth
    for k,v in d.items():
        if isinstance(v, dict):
            lines.append(f'{ind}"{escape(k)}"')
            lines.append(f'{ind}{{')
            lines.extend(dump(v, depth+1))
            lines.append(f'{ind}}}')
        else:
            lines.append(f'{ind}"{escape(k)}"\t\t"{escape(v)}"')
    return lines

def get_or_create(d, path):
    cur=d
    for k in path:
        v=cur.get(k)
        if not isinstance(v, dict):
            v=OrderedDict(); cur[k]=v
        cur=v
    return cur

def find_ci_key(d, wanted):
    w=wanted.lower()
    for k in d:
        if k.lower()==w:
            return k
    return wanted

def atomic_write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if os.path.exists(path):
        bak=path+".wand-native.bak"
        if not os.path.exists(bak):
            shutil.copy2(path,bak)
    fd,tmp=tempfile.mkstemp(prefix=".wand-vdf-", dir=os.path.dirname(path))
    try:
        with os.fdopen(fd,"w",encoding="utf-8",newline="\n") as f:
            f.write(data)
            f.flush(); os.fsync(f.fileno())
        os.replace(tmp,path)
    finally:
        if os.path.exists(tmp): os.unlink(tmp)

def load(path):
    if not os.path.exists(path):
        return OrderedDict()
    with open(path,"r",encoding="utf-8",errors="replace") as f:
        return parse(f.read())

def write(path,d):
    atomic_write(path, "\n".join(dump(d))+"\n")

def set_mapping(config_path, appid, tool):
    d=load(config_path)
    install_key=find_ci_key(d,"InstallConfigStore")
    root=get_or_create(d,[install_key])
    sw_key=find_ci_key(root,"Software")
    valve=get_or_create(root,[sw_key])
    valve_key=find_ci_key(valve,"Valve")
    steam=get_or_create(valve,[valve_key])
    steam_key=find_ci_key(steam,"Steam")
    steamobj=get_or_create(steam,[steam_key])
    compat_key=find_ci_key(steamobj,"CompatToolMapping")
    compat=get_or_create(steamobj,[compat_key])
    app=get_or_create(compat,[str(appid)])
    app["name"]=tool
    app["config"]=""
    app["priority"]="250"
    write(config_path,d)

def set_launch(local_path, appid, launch):
    d=load(local_path)
    user_key=find_ci_key(d,"UserLocalConfigStore")
    user=get_or_create(d,[user_key])
    sw_key=find_ci_key(user,"Software")
    sw=get_or_create(user,[sw_key])
    valve_key=find_ci_key(sw,"Valve")
    valve=get_or_create(sw,[valve_key])
    steam_key=find_ci_key(valve,"Steam")
    steam=get_or_create(valve,[steam_key])
    apps_key=find_ci_key(steam,"apps")
    apps=get_or_create(steam,[apps_key])
    app=get_or_create(apps,[str(appid)])
    app["LaunchOptions"]=launch
    write(local_path,d)

def read_path(d,path):
    cur=d
    for wanted in path:
        if not isinstance(cur,dict): return None
        key=next((k for k in cur if k.lower()==wanted.lower()),None)
        if key is None: return None
        cur=cur[key]
    return cur

def main():
    if len(sys.argv)<2:
        raise SystemExit("usage: wand-vdf.py set|check ...")
    cmd=sys.argv[1]
    if cmd=="set":
        if len(sys.argv)!=8:
            raise SystemExit("set CONFIG LOCALCONFIG APPID TOOL LAUNCH BACKUPTAG")
        _,_,config,local,appid,tool,launch,_tag=sys.argv
        set_mapping(config,appid,tool)
        set_launch(local,appid,launch)
        print("VDF_UPDATE_OK")
    elif cmd=="check":
        if len(sys.argv)!=6:
            raise SystemExit("check CONFIG LOCALCONFIG APPID TOOL")
        _,_,config,local,appid,tool=sys.argv
        c=load(config); l=load(local)
        mapping=read_path(c,["InstallConfigStore","Software","Valve","Steam","CompatToolMapping",appid,"name"])
        launch=read_path(l,["UserLocalConfigStore","Software","Valve","Steam","apps",appid,"LaunchOptions"])
        print(f"mapping={mapping or ''}")
        print(f"launch={launch or ''}")
        if mapping==tool and launch and "wand-steam-wrap" in launch:
            print("VDF_CHECK_OK")
            return
        raise SystemExit(3)
    else:
        raise SystemExit("unknown command")

if __name__=="__main__":
    main()
