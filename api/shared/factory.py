import os
import motor.motor_asyncio
from pymongo import MongoClient
from redis import Redis
from .env import *
from .modules.jackett import AsyncJackett

jackett = AsyncJackett(apikey=JACKETT_API_KEY)

# Initialize Redis
redis = Redis(
    host=REDIS_HOST,
    password=REDIS_PASSWORD,
    port=REDIS_PORT,
    db=0,
)


def get_db():
    # Initialize MongoDB
    mongo_client = motor.motor_asyncio.AsyncIOMotorClient(MONGO_DATABASE_URI)
    db = mongo_client[MONGO_DATABASE_NAME]
    return db


db = get_db()

# Background torrent callbacks run outside the API event loop, so they need a
# synchronous client. Motor calls from those threads return unresolved futures.
sync_db = MongoClient(MONGO_DATABASE_URI)[MONGO_DATABASE_NAME]
