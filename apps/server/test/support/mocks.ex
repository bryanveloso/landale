import Hammox

# Define behaviours for mocking
defmock(Server.Mocks.OBSMock, for: Server.Services.OBSBehaviour)
defmock(Server.Mocks.TwitchMock, for: Server.Services.TwitchBehaviour)
defmock(Server.Mocks.IronmonTCPMock, for: Server.Services.IronmonTCPBehaviour)
defmock(Server.Mocks.RainwaveMock, for: Server.Services.RainwaveBehaviour)
