package dev.hydrocap.app.sync

/** One atomic authority shared by initial reservation and every engine job. */
class CapJobAdmission {
    private var reserved=false
    private var running=false
    @Synchronized fun reserveInitial():Boolean { if(reserved || running) return false; reserved=true; return true }
    @Synchronized fun acquire(initial:Boolean=false):Boolean {
        if(running || reserved && !initial || initial && !reserved) return false
        running=true; return true
    }
    @Synchronized fun releaseJob() { running=false }
    @Synchronized fun releaseInitial() { reserved=false }
}

/** Service stop ownership accounts for duplicate Android start IDs without destroying the first job. */
class ServiceJobOwner {
    private var generation=0L
    private var active:Long?=null
    private var latestStartId=0
    @Synchronized fun admit(startId:Int):Long? {
        latestStartId=maxOf(latestStartId,startId)
        if(active!=null) return null
        val token=++generation; active=token; return token
    }
    @Synchronized fun finish(token:Long):Int? {
        if(active!=token) return null
        active=null; return latestStartId
    }
    @Synchronized fun isActive()=active!=null
}
