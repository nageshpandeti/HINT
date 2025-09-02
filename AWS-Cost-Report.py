import boto3
from datetime import datetime, timedelta

ce = boto3.client("ce", region_name="us-east-1")

def get_cost():
    start = (datetime.today() - timedelta(days=7)).strftime("%Y-%m-%d")
    end = datetime.today().strftime("%Y-%m-%d")

    result = ce.get_cost_and_usage(
        TimePeriod={"Start": start, "End": end},
        Granularity="DAILY",
        Metrics=["UnblendedCost"]
    )

    for day in result["ResultsByTime"]:
        print(f"{day['TimePeriod']['Start']} : ${day['Total']['UnblendedCost']['Amount']}")

get_cost()
