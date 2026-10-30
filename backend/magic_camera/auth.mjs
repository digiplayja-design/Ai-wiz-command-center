const operations=new Set(['auth/signin','auth/signup','auth/refresh','auth/signout','auth/password-reset','account/delete-request']);
export function magicAuthAlias(req,res,next){
 const [path,query]=String(req.url||'').split('?',2);
 if(!path.startsWith('/api/magic-account/'))return next();
 const operation=path.slice('/api/magic-account/'.length);
 if(req.method!=='POST'||!operations.has(operation))return res.status(404).json({error:'Account operation not found.'});
 req.headers['x-korlix-app']='magic_camera';req.body={...req.body,client_app:'magic_camera'};
 req.url='/api/'+operation+(query?'?'+query:'');next();
}
export function magicAppRouteAllowed(req){
 const method=String(req.method||'').toUpperCase(),path=String(req.originalUrl||req.url||'').split('?')[0];
 if(method==='POST'&&['auth/refresh','auth/signout','account/delete-request'].some(x=>path==='/api/magic-account/'+x))return true;
 if(path==='/api/magic-camera')return ['GET','HEAD','POST'].includes(method);
 if(/^\/api\/magic-camera\/requests\/[0-9a-f-]{36}$/.test(path))return ['GET','HEAD'].includes(method);
 if(/^\/api\/magic-camera\/[0-9a-f-]{36}(\/image|\/report)?$/.test(path))return ['GET','HEAD','POST','DELETE'].includes(method);
 return /^\/api\/magic-camera\/billing\/(google|apple)\/(status|prepare|verify|restore)$/.test(path)&&['GET','HEAD','POST'].includes(method);
}
