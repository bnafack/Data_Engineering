import json
import urllib.parse
import boto3
import io 
import csv


print('Loading function')

s3 = boto3.client('s3')


def lambda_handler(event, context):
    print("Received event: " + json.dumps(event, indent=2))
    # Extract the SQS message body (which is a JSON string)
    body_str = event['Records'][0]['body']
    
    # Parse the string into a dict
    body_json = json.loads(body_str)

    # Get the S3 object key
    raw_key = body_json['Records'][0]['s3']['object']['key']
        
    # Now access the inner S3 event
    bucket = body_json['Records'][0]['s3']['bucket']['name']

    # Decode the URL-encoded key
    key= urllib.parse.unquote_plus(raw_key, encoding='utf-8')
    print(bucket)
    print(key)
    try:
        response = s3.get_object(Bucket=bucket, Key=key)
        print("CONTENT TYPE: " + response['ContentType'])

        data = response['Body'].read().decode('utf-8')
        reader = csv.reader(io.StringIO(data))
        next(reader)
        for row in reader:
            #print(str.format("date- {}, count: ",row[0], row[1]))
            print (row)

        return response['ContentType']
    except Exception as e:
        print(e)
        print('Error getting object {} from bucket {}. Make sure they exist and your bucket is in the same region as this function.'.format(key, bucket))
        raise e