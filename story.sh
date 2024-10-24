#!/bin/bash

# 색상 설정
export RED='\033[0;31m'  # Red
export GREEN='\033[0;32m'  # Green
export YELLOW='\033[1;33m'  # Yellow
export BLUE='\033[0;34m'  # Blue
export MAGENTA='\033[0;35m'  # Magenta
export NC='\033[0m'  # No Color
BOLD=$(tput bold)
CYAN='\033[0;36m'  # Cyan


# 필요한 패키지 설치
sudo apt update && sudo apt-get update
sudo apt install curl git make jq build-essential gcc unzip wget lz4 aria2 -y

# Story-Geth 설치
echo -e "${BOLD}${CYAN}Story-Geth 설치 중...${NC}"
wget https://story-geth-binaries.s3.us-west-1.amazonaws.com/geth-public/geth-linux-amd64-0.10.0-afaa40a.tar.gz
tar -xzvf geth-linux-amd64-0.10.0-afaa40a.tar.gz
mkdir -p $HOME/go/bin
echo 'export PATH=$PATH:$HOME/go/bin' >> $HOME/.bash_profile
sudo cp geth-linux-amd64-0.10.0-afaa40a/geth $HOME/go/bin/story-geth

# Story 설치
echo -e "${BOLD}${CYAN}Story 설치 중...${NC}"
wget https://story-geth-binaries.s3.us-west-1.amazonaws.com/story-public/story-linux-amd64-0.11.0-aac4bfe.tar.gz
tar -xzvf story-linux-amd64-0.11.0-aac4bfe.tar.gz
sudo cp story-linux-amd64-0.11.0-aac4bfe/story $HOME/go/bin/story

# 환경 변수 등록
echo -e "${BOLD}${CYAN}환경 변수 등록 중...${NC}"
source ~/.bash_profile

# Story 설정
echo -e "${BOLD}${CYAN}Story 설정 중...${NC}"
read -p "등록할 모니커(밸리데이터명)를 입력하세요: " NODE_NAME
story init --network iliad --moniker $NODE_NAME

# Story-geth 서비스 설정
echo -e "${BOLD}${CYAN}Story-geth 서비스 설정 중...${NC}"
sudo tee /etc/systemd/system/story-geth.service > /dev/null <<EOF
[Unit]
Description=Story Geth Client
After=network.target

[Service]
User=root
ExecStart=/root/go/bin/story-geth --iliad --syncmode full
Restart=on-failure
RestartSec=3
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF

# Story-geth 서비스 등록 및 시작
echo -e "${BOLD}${CYAN}Story-geth 서비스 등록 및 시작 중...${NC}"
sudo systemctl daemon-reload
sudo systemctl start story-geth
sudo systemctl enable story-geth

# 상태 확인
echo -e "${BOLD}${CYAN}상태 확인 중...${NC}"
sudo systemctl status story-geth
echo -e "${BOLD}${CYAN}스테이터스를 체크하려면 다음명령어를 입력하세요.${NC}"
echo -e "${BOLD}${CYAN}'curl localhost:26657/status | jq'${NC}"

echo -e "${BOLD}${YELLOW}스냅샷 및 데이터 마이그레이션을 진행합니다. 계속 진행하려면 Enter 키를 누르세요...${NC}"
# ㄱ. 서비스 중지
echo -e "${BOLD}${CYAN}서비스 중지 중...${NC}"
sudo systemctl stop story-geth
sudo systemctl stop story

# ㄴ. Validator 정보 백업
echo -e "${BOLD}${GREEN}Validator 정보 백업중...${NC}"
sudo cp $HOME/.story/story/data/priv_validator_state.json $HOME/.story/priv_validator_state.json.backup

# ㄷ. 기존 블록 데이터 삭제
echo -e "${BOLD}${RED}기존 블록데이터 삭제중...${NC}"
sudo rm -rf $HOME/.story/geth/iliad/geth/chaindata
sudo rm -rf $HOME/.story/story/data

# ㄹ. 스냅샷 압축파일 다운로드 
echo -e "${BOLD}${CYAN}스냅샷 파일 다운로드중...${NC}"
wget -O Geth_snapshot.lz4 https://story.josephtran.co/Geth_snapshot.lz4
wget -O story_snapshot.lz4 https://snapshots.mandragora.io/story_snapshot.lz4

# ㅁ. 디렉터리에 마이그레이션 진행
# 이 부분은 한 줄씩 진행하세요. 그리고 결과가 모두 나올 때까지 기다리세요.
echo -e "${BOLD}${CYAN}마이그레이션을 진행합니다...${NC}"
lz4 -c -d Geth_snapshot.lz4 | tar -x -C $HOME/.story/geth/iliad/geth
# 결과가 나올 때까지 기다리세요.
read -p "첫 번째 마이그레이션이 완료되었습니다. 계속 진행하려면 Enter 키를 누르세요..."
lz4 -c -d story_snapshot.lz4 | tar -x -C $HOME/.story/story
# 결과가 나올 때까지 기다리세요.
read -p "두 번째 마이그레이션이 완료되었습니다. 계속 진행하려면 Enter 키를 누르세요..."

# ㅂ. 압축파일 삭제
echo -e "${BOLD}${CYAN}압축파일 삭제중...${NC}"
sudo rm -v Geth_snapshot.lz4
sudo rm -v story_snapshot.lz4

# ㅅ. Json 파일 복구
echo -e "${BOLD}${GREEN}Json파일 복구중...${NC}"
sudo cp $HOME/.story/priv_validator_state.json.backup $HOME/.story/story/data/priv_validator_state.json

# 12) Story-geth 재실행
echo -e "${BOLD}${CYAN}geth를 재실행합니다...${NC}"
sudo systemctl daemon-reload && \
sudo systemctl start story-geth && \
sudo systemctl enable story-geth && \
sudo systemctl status story-geth

# 13) Story 재실행
echo -e "${BOLD}${CYAN}노드를 재실행합니다...${NC}"
sudo systemctl daemon-reload && \
sudo systemctl start story && \
sudo systemctl enable story && \
sudo systemctl status story

# 14) 동기화 상태 확인
echo -e "${BOLD}${CYAN}동기화 상태를 확인합니다...${NC}"
curl localhost:26657/status | jq

# 15) 로그 확인 (한 번만 출력)
echo -e "${BOLD}${YELLOW}로그 확인 중...${NC}"
sudo journalctl -u story-geth.service -o cat
sudo journalctl -u story.service -o cat


echo -e "${BOLD}${CYAN}https://passport.gitcoin.co/#/dashboard${NC}"
read -p "위 사이트에 접속하여 humanity 스코어를 10점이상 쌓으세요(엔터)"
echo -e "${BOLD}${CYAN}https://faucet.story.foundation/${NC}"
read -p "위 사이트에 접속하여 Faucet을 받아주세요(엔터)"
read -p "Faucet을 받으신 후 총 2IP를 모아서 Validator 월렛에 전송하세요(엔터)"

echo -e "${BOLD}${CYAN}밸리데이터 프라이빗키를 따로 저장해두세요.${NC}"
# EVM 키 내보내기
story validator export --export-evm-key
# 프라이빗 키 확인
sudo cat /root/.story/story/config/private_key.txt
read -p "출력된 프라이빗키를 입력하세요: " privatekey
export privatekey
story validator create --stake 1464843750000000000 --private-key "$privatekey"

read -p "출력된 프라이빗키를 메타마스크에 추가하세요.(엔터)"
read -p "해당 월렛에 2IP이상을 전송하세요.(엔터)"

echo -e "${BOLD}${CYAN}밸리데이터 등록을 확인합니다.${NC}"
sudo cat /root/.story/story/config/priv_validator_key.json
read -p "출력된 address를 저장해두세요.(엔터)"
echo -e "${BOLD}${CYAN}1.해당 사이트에 접속하세요: https://testnet.story.explorers.guru/validators${NC}"
echo -e "${BOLD}${CYAN}2.검색에 address를 입력하시고 validator 닉네임을 복사하세요${NC}"
echo -e "${BOLD}${CYAN}3.Validator List에서 inactive를 선택하시고 valdator 닉네임을 검색하세요${NC}"

echo -e "${GREEN}모든 작업이 완료되었습니다. 컨트롤+A+D로 스크린을 분리해주세요.${NC}"
echo -e "${GREEN}스크립트작성자-https://t.me/kjkresearch${NC}"
