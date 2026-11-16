# Builds two weeks of sample meals, weigh-ins and water for App Store screenshots. Usage: make-sample.py <ios dir> <out.json> [YYYY-MM-DD]
import json,sys,uuid,datetime as dt
ios,out=sys.argv[1],sys.argv[2]
m=json.load(open(ios+'/MacroMenu/MenuData.json'))['foods']; g=json.load(open(ios+'/MacroMenu/GenericFoods.json'))
def M(name,chain): return next(f for f in m if f['name']==name and f['chain']==chain)
def G(name): return next(f for f in g if f['name']==name)
ref=dt.datetime(2001,1,1,tzinfo=dt.timezone.utc); tz=dt.timezone(dt.timedelta(hours=11))
today=dt.date.fromisoformat(sys.argv[3]) if len(sys.argv)>3 else dt.date.today()
U=lambda: str(uuid.uuid4()).upper()
def baked(f,q):
    f=dict(f)
    for k in ('cal','p','c','f'): f[k]=round(f[k]*q)
    f['kj']=round(f['cal']*4.184)
    if 'nut' in f: f['nut']={k:round(v*q,1) for k,v in f['nut'].items() if isinstance(v,(int,float))}
    f.pop('modifiers',None)
    if q!=1 and f.get('serve'): f['serve']=f"{q:g} × {f['serve']}"
    return f
def entry(day,hour,minute,meal,name,items):
    t=(dt.datetime(day.year,day.month,day.day,hour,minute,tzinfo=tz)-ref).total_seconds()
    return {"id":U(),"mealTime":meal,"time":t,"name":name,"items":[{"food":baked(f,q),"id":U(),"quantity":1} for f,q in items]}
bf=[("Oats and banana",[(G('Rolled oats'),0.6),(G('Banana'),1),(G('Greek yoghurt, plain, no fat'),2),(G('Whey protein powder'),0.3)]),
    ("Eggs on toast",[(G('Egg, scrambled'),3),(G('Wholemeal bread'),2),(G('Greek yoghurt, plain, no fat'),2)])]
lunch=[("Grilled Chicken Burrito Bowl",[(M('Grilled Chicken Burrito Bowl','gyg'),1)]),
       ("Zinger Protein Bowl",[(M('Zinger Protein Bowl','kfc'),1)]),
       ("Chicken Salad Bowl",[(M('Chicken Salad Bowl','oporto'),1)]),
       ("Avo Parmesan Crunch with Chicken",[(M('Avo Parmesan Crunch with Chicken','nandos'),1),(G('Banana'),1)])]
dinner=[("Chicken and rice",[(G('Chicken breast, cooked'),2),(G('White rice, cooked'),2.5)]),
        ("Half Chicken",[(M('Half Chicken','oporto'),1),(G('White rice, cooked'),1.5)]),
        ("Big Mac",[(M('Big Mac','mcd'),1)]),
        ("Steak and rice",[(G('Sirloin steak, lean, cooked'),2),(G('White rice, cooked'),2.5)])]
snack=[("Apple and almonds",[(G('Apple'),1),(G('Almonds'),1)]),("Greek yoghurt",[(G('Greek yoghurt, plain'),2),(G('Banana'),1)]),
       ("Protein shake",[(G('Whey protein powder'),0.3),(G('Milk, skim'),1)])]
logs={}
for i in range(13,-1,-1):
    d=today-dt.timedelta(days=i)
    if i in (9,12): continue
    es=[entry(d,7,40,"breakfast",*bf[i%2]),entry(d,12,35,"lunch",*lunch[i%4])]
    if i>0: es+=[entry(d,15,30,"snacks",*snack[i%3]),entry(d,19,10,"dinner",*dinner[i%4])]
    logs[d.isoformat()]=es
kgs=[86.4,86.0,85.9,85.3,85.5,84.9,84.6,84.8,84.2,84.0,83.7,83.9,83.4,83.1]
weights=[]
for n,kg in enumerate(kgs):
    d=today-dt.timedelta(days=3*(len(kgs)-1-n))
    weights.append({"kg":kg,"id":U(),"date":(dt.datetime(d.year,d.month,d.day,7,5,tzinfo=tz)-ref).total_seconds()})
monday=lambda d: (d-dt.timedelta(days=d.weekday())).isoformat()
start=today-dt.timedelta(days=57)
state={"version":2,"foods":[],"meals":[],"tray":[],"logs":logs,"weights":weights,
 "goalSets":[{"minimums":["p","fibre"],"mealCal":500,"mealProtein":40,"name":"Every day","values":{"cal":2200,"p":150},"id":U()}],
 "dayGoals":{},"weightGoal":{"startKg":88,"set":(dt.datetime(start.year,start.month,start.day,tzinfo=tz)-ref).total_seconds(),"kg":80},
 "celebrated":["week:"+monday(today-dt.timedelta(days=7*k)) for k in (2,1,0)],
 "water":{(today-dt.timedelta(days=i)).isoformat():v for i,v in enumerate([1250,2000,1750,2250,1500,2000,1750])}}
json.dump(state,open(out,'w'))
for k,es in logs.items():
    print(k, sum(it['food']['cal'] for e in es for it in e['items']), sum(it['food']['p'] for e in es for it in e['items']))
