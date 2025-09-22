# TODO

** common
    - fix no image: https://img3.javmost.com/images/480/GAS-499.webp
    - add config (use proxi)
    

** change db playlist -> collection
    - id
    - type              -- playlist | actress_fav
    - name
    - video_id
    - created_at
    - updated_at

** change db history -> activity
    - id
    - type              -- todo | download | relapse
    - content           -- dynamic (text/json)
    - created_at
    - updated_at

** remove db relapse -> join to activity