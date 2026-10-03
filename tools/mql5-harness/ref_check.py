import sys
def fixed(path,S,comm,SL,TP,opt):
    slu=-SL; hasTP=TP>0
    for (o,f,a,c) in path:
        uO,uF,uA=o-S,f-S,a-S
        if uO<=slu: return -1,(uO-comm)/SL,0
        if hasTP and uO>=TP: return 1,(uO-comm)/SL,0
        hs=uA<=slu; ht=hasTP and uF>=TP
        if hs and ht:
            return (1,(TP-comm)/SL,2) if opt else (-1,(slu-comm)/SL,2)
        if hs: return -1,(slu-comm)/SL,0
        if ht: return 1,(TP-comm)/SL,0
    uC=path[-1][3]-S
    return 0,(uC-comm)/SL,1
def tpoint(sl,p,act,dist,step):
    if p<act: return sl
    ns=p-dist
    return ns if ns>sl+step else sl
def tclimb(sl,h,act,dist,step):
    # salita continua fino a h: l'EA sposta lo stop a gradini (prezzo-dist > stop+step), non "massimo-dist"
    if h<act: return sl
    if step<=0: return max(sl,h-dist)
    while True:
        p=max(act,sl+dist+step)
        if p>h: return sl
        sl=p-dist
def trail(path,S,comm,SL,TP,act,dist,step,opt):
    sl=-SL; hasTP=TP>0; fl=0
    for (o,f,a,c) in path:
        uO,uF,uA=o-S,f-S,a-S
        if uO<=sl: return -1,(uO-comm)/SL,fl
        if hasTP and uO>=TP: return 1,(uO-comm)/SL,fl
        sl=tpoint(sl,uO,act,dist,step)
        if not opt:
            # peggiore: estremo avverso contro lo stop corrente, poi TP, poi gradini, poi avverso contro il nuovo stop
            if uA<=sl: return -1,(sl-comm)/SL,(2 if (hasTP and uF>=TP) else 0)
            if hasTP and uF>=TP: return 1,(TP-comm)/SL,0
            sl=tclimb(sl,uF,act,dist,step)
            if uA<=sl: return -1,(sl-comm)/SL,2
        else:
            if hasTP and uF>=TP: return 1,(TP-comm)/SL,(2 if uA<=sl else 0)
            if uA<=sl: return -1,(sl-comm)/SL,0
            sl=tclimb(sl,uF,act,dist,step)
    uC=path[-1][3]-S
    return 0,(uC-comm)/SL,1
lines=open('simcases.txt').read().split('\n')
i=0; n=0; bad=0; L=40
while i<len(lines) and lines[i].startswith('C'):
    h=lines[i].split()
    opt=int(h[1]); S,comm,SL,TP,act,dist,step=map(float,h[2:9])
    c1,R1,fl1=int(h[10]),float(h[11]),int(h[12]); c2,R2,fl2=int(h[14]),float(h[15]),int(h[16])
    path=[tuple(map(float,lines[i+1+j].split()[1:])) for j in range(L)]
    r1=fixed(path,S,comm,SL,TP,opt); r2=trail(path,S,comm,SL,TP,act,dist,step,opt)
    ok1=(r1[0]==c1 and abs(r1[1]-R1)<1e-8 and r1[2]==fl1)
    ok2=(r2[0]==c2 and abs(r2[1]-R2)<1e-8 and r2[2]==fl2)
    if not (ok1 and ok2):
        bad+=1
        if bad<=5: print("MISMATCH",n,opt,(c1,R1,fl1),r1,(c2,R2,fl2),r2)
    n+=1; i+=1+L
print("cases",n,"mismatches",bad)
