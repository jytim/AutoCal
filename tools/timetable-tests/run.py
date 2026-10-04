import json,subprocess,base64,sys
P=open('/tmp/p6.txt').read()
def shrink(f):
    out='s_'+f
    subprocess.run(['../ct/cropt',f,out,'0','0','99999','99999','1600'],capture_output=True)
    return out
def call(img):
    b64=base64.b64encode(open(img,'rb').read()).decode()
    body={"model":"nvidia-Qwen3.6-35B-A3B-NVFP4","max_tokens":2500,"temperature":0,"chat_template_kwargs":{"enable_thinking":False},
     "messages":[{"role":"system","content":P},{"role":"user","content":[{"type":"text","text":"這是我的課表截圖，請把每一門課抽出來。"},{"type":"image_url","image_url":{"url":"data:image/jpeg;base64,"+b64}}]}]}
    r=subprocess.run(['curl','-s','-m','180','http://<內網主機A>:8990/v1/chat/completions','-H','Content-Type: application/json','-d',json.dumps(body)],capture_output=True,text=True)
    c=json.loads(r.stdout)['choices'][0]['message']['content']
    return json.loads(c[c.index('['):c.rindex(']')+1])
for sc in json.load(open('manifest.json')):
    for im in sc['images']:
        r=call(shrink(im)); json.dump(r,open('raw_'+im.replace('.jpg','.json'),'w'),ensure_ascii=False)
        print(im,len(r),'drafts',flush=True)
