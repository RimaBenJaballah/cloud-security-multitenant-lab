import base64
import gzip
import json
import os
import boto3

logs_client = boto3.client("logs")
LOG_GROUP = os.environ["LOG_GROUP_NAME"]


def handler(event, context):
    payload = base64.b64decode(event["awslogs"]["data"])
    data = json.loads(gzip.decompress(payload))

    log_events = []
    for e in data.get("logEvents", []):
        log_events.append({
            "timestamp": e["timestamp"],
            "message": e["message"],
        })

    if not log_events:
        return

    stream_name = "forwarded-" + context.aws_request_id
    try:
        logs_client.create_log_stream(
            logGroupName=LOG_GROUP, logStreamName=stream_name
        )
    except logs_client.exceptions.ResourceAlreadyExistsException:
        pass

    logs_client.put_log_events(
        logGroupName=LOG_GROUP,
        logStreamName=stream_name,
        logEvents=sorted(log_events, key=lambda x: x["timestamp"]),
    )