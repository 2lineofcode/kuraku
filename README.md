# r18

## DB design

* **library**
    - ss
    - asd
    - asd
* **videos**
    - asd
    - as

## workflow design

#### [step1]

- select folder
- scan video on that folder
- insert into (db library)
- loop video on folder selected -> insert into videos

#### [step2]

looping from table videos -> getVideo from `r18.db`
if (found) -> update table videos
else -> call api

#### [step3]
