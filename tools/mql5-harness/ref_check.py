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
def trail(path,S,comm,SL,TP,act,dist,step,opt):
    sl=-SL; hasTP=TP>0; peak=-1e300; fl=0
    for (o,f,a,c) in path:
        uO,uF,uA=o-S,f-S,a-S
        if uO<=sl: return -1,(uO-comm)/SL,fl
        if hasTP and uO>=TP: return 1,(uO-comm)/SL,fl
        if not opt:
            # worst path: adverse extreme vs current stop first, then TP, then ratchet, then adverse vs new stop
            if uA<=sl: return -1,(sl-comm)/SL,(2 if (hasTP and uF>=TP) else 0)
            if hasTP and uF>=TP: return 1,(TP-comm)/SL,0
            peak=max(peak,uF)
            if peak>=act and peak-dist>sl+step: sl=peak-dist
            if uA<=sl: return -1,(sl-comm)/SL,2
        else:
            if hasTP and uF>=TP: return 1,(TP-comm)/SL,(2 if uA<=sl else 0)
            if uA<=sl: return -1,(sl-comm)/SL,0
            peak=max(peak,uF)
            if peak>=act and peak-dist>sl+step: sl=peak-dist
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
