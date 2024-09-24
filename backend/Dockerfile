FROM python:3.8

RUN pip install snowflake-snowpark-python flask

COPY ./src /src

WORKDIR /src

# HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 CMD [ "curl", "-f", "http://localhost:8001/", "||", "exit", "1" ]
EXPOSE 8001
CMD python app.py